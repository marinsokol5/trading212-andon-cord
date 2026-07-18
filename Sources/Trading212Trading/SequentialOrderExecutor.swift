import Foundation
import Trading212Core

public struct TradeExecutionOutcome: Equatable, Sendable {
    public let receipt: TradeReceipt

    public init(receipt: TradeReceipt) {
        self.receipt = receipt
    }

    public var succeeded: Bool { receipt.status == .completed }
    public var isAmbiguous: Bool { receipt.status == .stoppedAmbiguous }
}

public enum TradeExecutionError: Error, Equatable, Sendable, CustomStringConvertible {
    case journal(String)

    public var description: String {
        switch self {
        case .journal(let message):
            "local receipt/audit persistence failed; no later order was submitted: \(message)"
        }
    }
}

/// Submits orders one at a time. There is deliberately no task group, parallelism,
/// or generic retry wrapper anywhere on this path.
public struct SequentialOrderExecutor: Sendable {
    private let submitter: any MarketOrderSubmitting
    private let journal: any TradeJournaling
    private let sleeper: any TradingSleeper
    private let now: @Sendable () -> Date
    private let fallbackDelay: TimeInterval

    public init(
        submitter: any MarketOrderSubmitting,
        journal: any TradeJournaling,
        sleeper: any TradingSleeper = TaskTradingSleeper(),
        now: @escaping @Sendable () -> Date = Date.init,
        fallbackDelay: TimeInterval = 1.25
    ) {
        self.submitter = submitter
        self.journal = journal
        self.sleeper = sleeper
        self.now = now
        self.fallbackDelay = max(0, fallbackDelay)
    }

    public func execute(
        action: TradingAction,
        environment: Trading212Environment,
        accountID: String,
        snapshotPath: String?,
        requests: [MarketOrderRequest],
        receiptID: UUID = UUID()
    ) async throws -> TradeExecutionOutcome {
        let startedAt = now()
        var receipt = TradeReceipt(
            id: receiptID,
            action: action,
            environment: environment,
            accountID: accountID,
            snapshotPath: snapshotPath,
            startedAt: startedAt,
            requests: requests
        )
        try await persist(
            receipt,
            event: event(for: receipt, kind: .runStarted, at: startedAt)
        )

        guard !requests.isEmpty else {
            let completedAt = now()
            receipt.status = .completed
            receipt.updatedAt = completedAt
            receipt.completedAt = completedAt
            try await persist(
                receipt,
                event: event(for: receipt, kind: .runCompleted, at: completedAt)
            )
            return TradeExecutionOutcome(receipt: receipt)
        }

        for index in requests.indices {
            let request = requests[index]
            let submittingAt = now()
            receipt.orders[index].state = .submitting(at: submittingAt)
            receipt.updatedAt = submittingAt
            try await persist(
                receipt,
                event: event(
                    for: receipt,
                    kind: .orderSubmitting,
                    at: submittingAt,
                    request: request,
                    index: index
                )
            )

            do {
                let submission = try await submitter.submit(request)
                let respondedAt = now()
                receipt.orders[index].brokerResult = .init(response: submission.response)
                if submission.response.status.isDefiniteFailure {
                    receipt.orders[index].state = .rejected(
                        message: "broker status \(submission.response.status.rawValue)",
                        brokerStatus: submission.response.status,
                        at: respondedAt
                    )
                    receipt.updatedAt = respondedAt
                    try await persist(
                        receipt,
                        event: event(
                            for: receipt,
                            kind: .orderRejected,
                            at: respondedAt,
                            request: request,
                            index: index,
                            message: "broker status \(submission.response.status.rawValue)"
                        )
                    )
                } else {
                    receipt.orders[index].state = .accepted(
                        orderID: submission.response.id,
                        brokerStatus: submission.response.status,
                        at: respondedAt
                    )
                    receipt.updatedAt = respondedAt
                    try await persist(
                        receipt,
                        event: event(
                            for: receipt,
                            kind: .orderAccepted,
                            at: respondedAt,
                            request: request,
                            index: index,
                            message: "broker status \(submission.response.status.rawValue)"
                        )
                    )
                }

                if index < requests.index(before: requests.endIndex) {
                    do {
                        try await pace(after: submission.rateLimit)
                    } catch {
                        let stoppedAt = now()
                        receipt.status = .stoppedBeforeSubmission
                        receipt.updatedAt = stoppedAt
                        receipt.completedAt = stoppedAt
                        try await persist(
                            receipt,
                            event: event(
                                for: receipt,
                                kind: .runStopped,
                                at: stoppedAt,
                                message: "order pacing was interrupted; remaining orders were not sent"
                            )
                        )
                        return TradeExecutionOutcome(receipt: receipt)
                    }
                }
            } catch let error as TradeExecutionError {
                // A receipt transition failed after a broker response. Stop
                // immediately; do not misclassify it and never submit a later order.
                throw error
            } catch let error as OrderSubmissionError {
                let failedAt = now()
                switch error {
                case .definiteRejection(_, let message, let rateLimit):
                    receipt.orders[index].state = .rejected(
                        message: message,
                        brokerStatus: nil,
                        at: failedAt
                    )
                    receipt.updatedAt = failedAt
                    try await persist(
                        receipt,
                        event: event(
                            for: receipt,
                            kind: .orderRejected,
                            at: failedAt,
                            request: request,
                            index: index,
                            message: message
                        )
                    )
                    // A definite 4xx rejection did not create an order. Continue
                    // the emergency run, matching the proven andon behavior.
                    if index < requests.index(before: requests.endIndex) {
                        do {
                            try await pace(after: rateLimit)
                        } catch {
                            let stoppedAt = now()
                            receipt.status = .stoppedBeforeSubmission
                            receipt.updatedAt = stoppedAt
                            receipt.completedAt = stoppedAt
                            try await persist(
                                receipt,
                                event: event(
                                    for: receipt,
                                    kind: .runStopped,
                                    at: stoppedAt,
                                    message: "order pacing was interrupted; remaining orders were not sent"
                                )
                            )
                            return TradeExecutionOutcome(receipt: receipt)
                        }
                    }
                    continue

                case .fatalBeforeSubmission(let message):
                    receipt.orders[index].state = .notSubmitted(message: message, at: failedAt)
                    receipt.status = .stoppedBeforeSubmission
                    receipt.updatedAt = failedAt
                    receipt.completedAt = failedAt
                    try await persist(
                        receipt,
                        event: event(
                            for: receipt,
                            kind: .runStopped,
                            at: failedAt,
                            request: request,
                            index: index,
                            message: message
                        )
                    )
                    return TradeExecutionOutcome(receipt: receipt)

                case .ambiguous(let message):
                    receipt.orders[index].state = .ambiguous(message: message, at: failedAt)
                    receipt.status = .stoppedAmbiguous
                    receipt.updatedAt = failedAt
                    receipt.completedAt = failedAt
                    try await persist(
                        receipt,
                        event: event(
                            for: receipt,
                            kind: .runStopped,
                            at: failedAt,
                            request: request,
                            index: index,
                            message: "ambiguous broker outcome; verify state before any retry"
                        )
                    )
                    return TradeExecutionOutcome(receipt: receipt)
                }
            } catch {
                // An injected/unknown submitter failure is conservatively ambiguous:
                // it may have thrown after transmitting the request.
                let failedAt = now()
                let message = "unknown submission failure; the order may have reached the broker"
                receipt.orders[index].state = .ambiguous(message: message, at: failedAt)
                receipt.status = .stoppedAmbiguous
                receipt.updatedAt = failedAt
                receipt.completedAt = failedAt
                try await persist(
                    receipt,
                    event: event(
                        for: receipt,
                        kind: .runStopped,
                        at: failedAt,
                        request: request,
                        index: index,
                        message: message
                    )
                )
                return TradeExecutionOutcome(receipt: receipt)
            }
        }

        let completedAt = now()
        receipt.status = receipt.rejectedCount > 0 ? .completedWithRejections : .completed
        receipt.updatedAt = completedAt
        receipt.completedAt = completedAt
        try await persist(
            receipt,
            event: event(for: receipt, kind: .runCompleted, at: completedAt)
        )
        return TradeExecutionOutcome(receipt: receipt)
    }

    private func pace(after rateLimit: OrderRateLimit) async throws {
        if let remaining = rateLimit.remaining, remaining <= 1 {
            let wait = max(1, (rateLimit.delay(at: now()) ?? fallbackDelay) + 1)
            try await sleeper.sleep(for: wait)
        } else if fallbackDelay > 0 {
            try await sleeper.sleep(for: fallbackDelay)
        }
    }

    private func persist(_ receipt: TradeReceipt, event: TradeAuditEvent) async throws {
        do {
            try await journal.record(receipt: receipt, event: event)
        } catch let error as TradeJournalError {
            throw TradeExecutionError.journal(error.description)
        } catch {
            throw TradeExecutionError.journal("receipt/audit store returned an error")
        }
    }

    private func event(
        for receipt: TradeReceipt,
        kind: TradeAuditEvent.Kind,
        at date: Date,
        request: MarketOrderRequest? = nil,
        index: Int? = nil,
        message: String? = nil
    ) -> TradeAuditEvent {
        TradeAuditEvent(
            timestamp: date,
            receiptID: receipt.id,
            action: receipt.action,
            environment: receipt.environment,
            kind: kind,
            ticker: request?.ticker,
            orderIndex: index,
            message: message
        )
    }
}
