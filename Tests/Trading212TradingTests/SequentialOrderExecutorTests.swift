import Foundation
import XCTest
import Trading212Core
@testable import Trading212Trading

@MainActor
final class SequentialOrderExecutorTests: XCTestCase {
    func testSequentialSuccessPersistsSubmittingBeforeEveryCall() async throws {
        let submitter = ScriptedSubmitter([
            .response(submission(id: "one")),
            .response(submission(id: "two")),
        ])
        let journal = RecordingJournal()
        let executor = SequentialOrderExecutor(
            submitter: submitter,
            journal: journal,
            sleeper: RecordingSleeper(),
            now: { Date(timeIntervalSince1970: 100) },
            fallbackDelay: 0
        )
        let outcome = try await executor.execute(
            action: .sellAll,
            environment: .demo,
            accountID: "account",
            snapshotPath: "/snapshot.json",
            requests: [
                .init(ticker: "A", quantity: -1),
                .init(ticker: "B", quantity: -2),
            ]
        )

        XCTAssertEqual(outcome.receipt.status, .completed)
        XCTAssertEqual(outcome.receipt.acceptedCount, 2)
        let submitted = await submitter.submittedRequests()
        XCTAssertEqual(submitted.map(\.ticker), ["A", "B"])
        let records = await journal.allRecords()
        XCTAssertEqual(records.map { $0.1.kind }, [
            .runStarted,
            .orderSubmitting,
            .orderAccepted,
            .orderSubmitting,
            .orderAccepted,
            .runCompleted,
        ])
        guard case .submitting = records[1].0.orders[0].state else {
            return XCTFail("submitting state must be durable before POST")
        }
    }

    func testBrokerRejectedStatusFailsRunButContinuesLaterOrders() async throws {
        let submitter = ScriptedSubmitter([
            .response(submission(id: "r", status: .rejected)),
            .response(submission(id: "f", status: .filled)),
        ])
        let outcome = try await SequentialOrderExecutor(
            submitter: submitter,
            journal: RecordingJournal(),
            sleeper: RecordingSleeper(),
            fallbackDelay: 0
        ).execute(
            action: .sellAll,
            environment: .demo,
            accountID: "1",
            snapshotPath: nil,
            requests: [
                .init(ticker: "A", quantity: -1),
                .init(ticker: "B", quantity: -1),
            ]
        )
        XCTAssertEqual(outcome.receipt.status, .completedWithRejections)
        XCTAssertEqual(outcome.receipt.rejectedCount, 1)
        XCTAssertEqual(outcome.receipt.acceptedCount, 1)
        let submitted = await submitter.submittedRequests()
        XCTAssertEqual(submitted.count, 2)
    }

    func testDefiniteHTTPRejectionContinuesLaterOrders() async throws {
        let submitter = ScriptedSubmitter([
            .error(.definiteRejection(
                status: 422,
                message: "quantity rejected",
                rateLimit: .init(remaining: 48)
            )),
            .response(submission()),
        ])
        let outcome = try await SequentialOrderExecutor(
            submitter: submitter,
            journal: RecordingJournal(),
            sleeper: RecordingSleeper(),
            fallbackDelay: 0
        ).execute(
            action: .buyAll,
            environment: .demo,
            accountID: "1",
            snapshotPath: "/in.json",
            requests: [
                .init(ticker: "A", quantity: 1),
                .init(ticker: "B", quantity: 1),
            ]
        )
        XCTAssertEqual(outcome.receipt.status, .completedWithRejections)
        let submitted = await submitter.submittedRequests()
        XCTAssertEqual(submitted.count, 2)
    }

    func testAmbiguousFailureStopsAndNeverSubmitsLaterOrder() async throws {
        let submitter = ScriptedSubmitter([
            .response(submission(id: "one")),
            .error(.ambiguous(message: "timeout; unknown outcome")),
            .response(submission(id: "must-not-run")),
        ])
        let outcome = try await SequentialOrderExecutor(
            submitter: submitter,
            journal: RecordingJournal(),
            sleeper: RecordingSleeper(),
            fallbackDelay: 0
        ).execute(
            action: .sellAll,
            environment: .demo,
            accountID: "1",
            snapshotPath: "/snapshot.json",
            requests: [
                .init(ticker: "A", quantity: -1),
                .init(ticker: "B", quantity: -1),
                .init(ticker: "C", quantity: -1),
            ]
        )

        XCTAssertEqual(outcome.receipt.status, .stoppedAmbiguous)
        XCTAssertTrue(outcome.isAmbiguous)
        XCTAssertEqual(outcome.receipt.notSent.map(\.ticker), ["C"])
        guard case .ambiguous = outcome.receipt.orders[1].state else {
            return XCTFail("failed order must remain visibly ambiguous")
        }
        let submitted = await submitter.submittedRequests()
        XCTAssertEqual(submitted.map(\.ticker), ["A", "B"])
    }

    func testUnknownSubmitterErrorIsConservativelyAmbiguous() async throws {
        let submitter = ScriptedSubmitter([.unknownError, .response(submission())])
        let outcome = try await SequentialOrderExecutor(
            submitter: submitter,
            journal: RecordingJournal(),
            sleeper: RecordingSleeper(),
            fallbackDelay: 0
        ).execute(
            action: .buyAll,
            environment: .demo,
            accountID: "1",
            snapshotPath: nil,
            requests: [
                .init(ticker: "A", quantity: 1),
                .init(ticker: "B", quantity: 1),
            ]
        )
        XCTAssertEqual(outcome.receipt.status, .stoppedAmbiguous)
        let submitted = await submitter.submittedRequests()
        XCTAssertEqual(submitted.count, 1)
    }

    func testJournalFailureBeforeSubmittingTransitionSendsZeroOrders() async throws {
        let submitter = ScriptedSubmitter([.response(submission())])
        let executor = SequentialOrderExecutor(
            submitter: submitter,
            journal: RecordingJournal(failAtCall: 0),
            sleeper: RecordingSleeper(),
            fallbackDelay: 0
        )
        do {
            _ = try await executor.execute(
                action: .sellAll,
                environment: .demo,
                accountID: "1",
                snapshotPath: nil,
                requests: [.init(ticker: "A", quantity: -1)]
            )
            XCTFail("journal failure should stop execution")
        } catch is TradeExecutionError {
            // Expected.
        }
        let submitted = await submitter.submittedRequests()
        XCTAssertTrue(submitted.isEmpty)
    }

    func testJournalFailureAfterBrokerResponseStopsBeforeLaterOrder() async throws {
        let submitter = ScriptedSubmitter([
            .response(submission()),
            .response(submission()),
        ])
        // Calls: runStarted=0, orderSubmitting=1, orderAccepted=2 (fails).
        let executor = SequentialOrderExecutor(
            submitter: submitter,
            journal: RecordingJournal(failAtCall: 2),
            sleeper: RecordingSleeper(),
            fallbackDelay: 0
        )
        do {
            _ = try await executor.execute(
                action: .buyAll,
                environment: .demo,
                accountID: "1",
                snapshotPath: nil,
                requests: [
                    .init(ticker: "A", quantity: 1),
                    .init(ticker: "B", quantity: 1),
                ]
            )
            XCTFail("journal failure should stop execution")
        } catch is TradeExecutionError {
            // Expected.
        }
        let submitted = await submitter.submittedRequests()
        XCTAssertEqual(submitted.map(\.ticker), ["A"])
    }

    func testRateLimitRemainingOneWaitsUntilResetBeforeNextOrder() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let sleeper = RecordingSleeper()
        let submitter = ScriptedSubmitter([
            .response(submission(remaining: 1, resetAt: Date(timeIntervalSince1970: 1_010))),
            .response(submission()),
        ])
        _ = try await SequentialOrderExecutor(
            submitter: submitter,
            journal: RecordingJournal(),
            sleeper: sleeper,
            now: { now },
            fallbackDelay: 0.3
        ).execute(
            action: .buyAll,
            environment: .demo,
            accountID: "1",
            snapshotPath: nil,
            requests: [
                .init(ticker: "A", quantity: 1),
                .init(ticker: "B", quantity: 1),
            ]
        )
        let durations = await sleeper.recordedDurations()
        XCTAssertEqual(durations, [11])
    }

    func testInterruptedRateLimitWaitStopsBeforeNextOrder() async throws {
        let sleeper = RecordingSleeper()
        await sleeper.setShouldThrow(true)
        let submitter = ScriptedSubmitter([
            .response(submission(remaining: 0, resetAt: Date(timeIntervalSince1970: 10))),
            .response(submission()),
        ])
        let outcome = try await SequentialOrderExecutor(
            submitter: submitter,
            journal: RecordingJournal(),
            sleeper: sleeper,
            now: { Date(timeIntervalSince1970: 0) },
            fallbackDelay: 0
        ).execute(
            action: .sellAll,
            environment: .demo,
            accountID: "1",
            snapshotPath: nil,
            requests: [
                .init(ticker: "A", quantity: -1),
                .init(ticker: "B", quantity: -1),
            ]
        )
        XCTAssertEqual(outcome.receipt.status, .stoppedBeforeSubmission)
        let submitted = await submitter.submittedRequests()
        XCTAssertEqual(submitted.map(\.ticker), ["A"])
    }
}
