import Foundation
import Trading212Core

public struct TradingSnapshotDocument: Equatable, Sendable, Codable {
    public static let schemaIdentifier = "com.marinsokol.trading212andoncord.portfolio-snapshot"
    public static let currentVersion = 1

    public enum Kind: String, Codable, Sendable {
        case current
        case preSale
    }

    public struct Account: Equatable, Sendable, Codable {
        public let id: String
        public let currency: String

        public init(id: String, currency: String) {
            self.id = id
            self.currency = currency
        }
    }

    public struct Totals: Equatable, Sendable, Codable {
        public let accountValue: Decimal
        public let freeCash: Decimal
        public let sellablePositionsValue: Decimal

        public init(accountValue: Decimal, freeCash: Decimal, sellablePositionsValue: Decimal) {
            self.accountValue = accountValue
            self.freeCash = freeCash
            self.sellablePositionsValue = sellablePositionsValue
        }

        private enum CodingKeys: String, CodingKey {
            case accountValue, freeCash, sellablePositionsValue
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            accountValue = try values.decodeDecimalString(forKey: .accountValue)
            freeCash = try values.decodeDecimalString(forKey: .freeCash)
            sellablePositionsValue = try values.decodeDecimalString(forKey: .sellablePositionsValue)
        }

        public func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encodeDecimalString(accountValue, forKey: .accountValue)
            try values.encodeDecimalString(freeCash, forKey: .freeCash)
            try values.encodeDecimalString(sellablePositionsValue, forKey: .sellablePositionsValue)
        }
    }

    public struct Position: Equatable, Sendable, Codable {
        public let ticker: String
        public let isin: String?
        public let name: String
        public let instrumentCurrency: String
        public let quantity: Decimal
        public let sellableQuantity: Decimal
        public let pieQuantity: Decimal
        public let nativePrice: Decimal?
        public let accountPricePerShare: Decimal
        public let sellableAccountValue: Decimal
        public let sellableWeight: Decimal

        public init(
            ticker: String,
            isin: String? = nil,
            name: String,
            instrumentCurrency: String,
            quantity: Decimal,
            sellableQuantity: Decimal,
            pieQuantity: Decimal,
            nativePrice: Decimal?,
            accountPricePerShare: Decimal,
            sellableAccountValue: Decimal,
            sellableWeight: Decimal
        ) {
            self.ticker = ticker
            self.isin = isin
            self.name = name
            self.instrumentCurrency = instrumentCurrency
            self.quantity = quantity
            self.sellableQuantity = sellableQuantity
            self.pieQuantity = pieQuantity
            self.nativePrice = nativePrice
            self.accountPricePerShare = accountPricePerShare
            self.sellableAccountValue = sellableAccountValue
            self.sellableWeight = sellableWeight
        }

        private enum CodingKeys: String, CodingKey {
            case ticker, isin, name, instrumentCurrency, quantity, sellableQuantity
            case pieQuantity, nativePrice, accountPricePerShare, sellableAccountValue
            case sellableWeight
        }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            ticker = try values.decode(String.self, forKey: .ticker)
            isin = try values.decodeIfPresent(String.self, forKey: .isin)
            name = try values.decode(String.self, forKey: .name)
            instrumentCurrency = try values.decode(String.self, forKey: .instrumentCurrency)
            quantity = try values.decodeDecimalString(forKey: .quantity)
            sellableQuantity = try values.decodeDecimalString(forKey: .sellableQuantity)
            pieQuantity = try values.decodeDecimalString(forKey: .pieQuantity)
            nativePrice = try values.decodeDecimalStringIfPresent(forKey: .nativePrice)
            accountPricePerShare = try values.decodeDecimalString(forKey: .accountPricePerShare)
            sellableAccountValue = try values.decodeDecimalString(forKey: .sellableAccountValue)
            sellableWeight = try values.decodeDecimalString(forKey: .sellableWeight)
        }

        public func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(ticker, forKey: .ticker)
            try values.encodeIfPresent(isin, forKey: .isin)
            try values.encode(name, forKey: .name)
            try values.encode(instrumentCurrency, forKey: .instrumentCurrency)
            try values.encodeDecimalString(quantity, forKey: .quantity)
            try values.encodeDecimalString(sellableQuantity, forKey: .sellableQuantity)
            try values.encodeDecimalString(pieQuantity, forKey: .pieQuantity)
            try values.encodeDecimalStringIfPresent(nativePrice, forKey: .nativePrice)
            try values.encodeDecimalString(accountPricePerShare, forKey: .accountPricePerShare)
            try values.encodeDecimalString(sellableAccountValue, forKey: .sellableAccountValue)
            try values.encodeDecimalString(sellableWeight, forKey: .sellableWeight)
        }
    }

    public let schema: String
    public let version: Int
    public let kind: Kind
    public let capturedAt: Date
    public let environment: Trading212Environment
    public let account: Account
    public let totals: Totals
    public let positions: [Position]

    public init(
        kind: Kind,
        capturedAt: Date,
        environment: Trading212Environment,
        account: Account,
        totals: Totals,
        positions: [Position]
    ) {
        schema = Self.schemaIdentifier
        version = Self.currentVersion
        self.kind = kind
        self.capturedAt = capturedAt
        self.environment = environment
        self.account = account
        self.totals = totals
        self.positions = positions
    }

    public init(
        schema: String,
        version: Int,
        kind: Kind,
        capturedAt: Date,
        environment: Trading212Environment,
        account: Account,
        totals: Totals,
        positions: [Position]
    ) {
        self.schema = schema
        self.version = version
        self.kind = kind
        self.capturedAt = capturedAt
        self.environment = environment
        self.account = account
        self.totals = totals
        self.positions = positions
    }
}

public enum TradingSnapshotSource: String, Sendable, Codable {
    case canonical
    case legacyAndonV1
}

public struct DecodedTradingSnapshot: Equatable, Sendable {
    public let document: TradingSnapshotDocument
    public let source: TradingSnapshotSource
    /// Legacy v1 did not carry an account id, so identity cannot be proven for it.
    public let accountIdentityVerified: Bool

    public init(
        document: TradingSnapshotDocument,
        source: TradingSnapshotSource,
        accountIdentityVerified: Bool
    ) {
        self.document = document
        self.source = source
        self.accountIdentityVerified = accountIdentityVerified
    }

    public func allocationsForBuy() throws -> [SnapshotAllocation] {
        try document.positions.compactMap { position in
            guard position.sellableQuantity > 0 || position.sellableAccountValue > 0 else {
                return nil
            }
            guard position.accountPricePerShare > 0 else {
                throw TradingSnapshotError.nonPositivePrice(position.ticker)
            }
            guard position.sellableWeight > 0 else {
                throw TradingSnapshotError.nonPositiveWeight(position.ticker)
            }
            return SnapshotAllocation(
                ticker: position.ticker,
                name: position.name,
                savedAccountPrice: position.accountPricePerShare,
                savedValue: position.sellableAccountValue,
                savedWeight: position.sellableWeight
            )
        }
    }
}

public enum TradingSnapshotError: Error, Equatable, Sendable, CustomStringConvertible {
    case invalidJSON
    case unknownSchema(String)
    case unsupportedVersion(Int)
    case invalidEnvironment(String)
    case environmentMismatch(expected: Trading212Environment, actual: Trading212Environment)
    case accountMismatch(expected: String, actual: String)
    case duplicateTicker(String)
    case emptyTicker
    case emptyAccountID
    case invalidCurrency(field: String, value: String)
    case invalidDecimal(field: String)
    case negativeValue(field: String, ticker: String?)
    case invalidQuantityRelationship(String)
    case inconsistentPositionValue(String)
    case inconsistentTotals(String)
    case weightExceedsOne(String)
    case inconsistentWeight(String)
    case nonPositivePrice(String)
    case nonPositiveWeight(String)
    case legacyMissingField(String)

    public var description: String {
        switch self {
        case .invalidJSON: "snapshot is not valid recognized JSON"
        case .unknownSchema(let value): "unknown snapshot schema \(value)"
        case .unsupportedVersion(let value): "unsupported snapshot version \(value)"
        case .invalidEnvironment(let value): "invalid snapshot environment \(value)"
        case .environmentMismatch(let expected, let actual):
            "snapshot environment is \(actual.rawValue), expected \(expected.rawValue)"
        case .accountMismatch(let expected, let actual):
            "snapshot account is \(actual), expected \(expected)"
        case .duplicateTicker(let ticker): "snapshot contains duplicate ticker \(ticker)"
        case .emptyTicker: "snapshot contains an empty ticker"
        case .emptyAccountID: "snapshot account id is empty"
        case .invalidCurrency(let field, let value):
            "snapshot \(field) is not an uppercase ISO 4217 currency code: \(value)"
        case .invalidDecimal(let field): "snapshot contains an invalid decimal at \(field)"
        case .negativeValue(let field, let ticker):
            "snapshot contains a negative \(field)\(ticker.map { " for \($0)" } ?? "")"
        case .invalidQuantityRelationship(let ticker):
            "snapshot quantities for \(ticker) are inconsistent (sellable and pie shares must fit within total shares)"
        case .inconsistentPositionValue(let ticker):
            "snapshot value for \(ticker) does not match sellable quantity × account price"
        case .inconsistentTotals(let field):
            "snapshot totals are inconsistent at \(field)"
        case .weightExceedsOne(let ticker):
            "snapshot weight for \(ticker) exceeds 1"
        case .inconsistentWeight(let ticker):
            "snapshot weight for \(ticker) does not match its value and sellable total"
        case .nonPositivePrice(let ticker): "snapshot price for \(ticker) must be positive"
        case .nonPositiveWeight(let ticker): "snapshot weight for \(ticker) must be positive"
        case .legacyMissingField(let field): "legacy snapshot is missing \(field)"
        }
    }
}

public enum TradingSnapshotCodec {
    public static func encode(_ snapshot: TradingSnapshotDocument) throws -> Data {
        try validate(snapshot, allowMissingAccountID: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var value = encoder.singleValueContainer()
            try value.encode(makeISO8601Formatter().string(from: date))
        }
        var data = try encoder.encode(snapshot)
        data.append(0x0A)
        return data
    }

    public static func decode(
        _ data: Data,
        expectedEnvironment: Trading212Environment? = nil,
        expectedAccountID: String? = nil
    ) throws -> DecodedTradingSnapshot {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            throw TradingSnapshotError.invalidJSON
        }

        let result: DecodedTradingSnapshot
        if dictionary.keys.contains("schema") {
            let schema = dictionary["schema"] as? String ?? "<invalid>"
            guard schema == TradingSnapshotDocument.schemaIdentifier else {
                throw TradingSnapshotError.unknownSchema(schema)
            }
            let version = dictionary["version"] as? Int ?? -1
            guard version == TradingSnapshotDocument.currentVersion else {
                throw TradingSnapshotError.unsupportedVersion(version)
            }
            result = try decodeCanonical(data)
        } else {
            result = try decodeLegacy(data)
        }
        try validate(
            result.document,
            allowMissingAccountID: result.source == .legacyAndonV1
        )

        if let expectedEnvironment, result.document.environment != expectedEnvironment {
            throw TradingSnapshotError.environmentMismatch(
                expected: expectedEnvironment,
                actual: result.document.environment
            )
        }
        if let expectedAccountID,
           result.source == .canonical,
           result.document.account.id != expectedAccountID {
            throw TradingSnapshotError.accountMismatch(
                expected: expectedAccountID,
                actual: result.document.account.id
            )
        }
        return result
    }

    private static func decodeCanonical(_ data: Data) throws -> DecodedTradingSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            guard let date = parseISO8601(value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "invalid ISO-8601 date"
                )
            }
            return date
        }
        let snapshot: TradingSnapshotDocument
        do {
            snapshot = try decoder.decode(TradingSnapshotDocument.self, from: data)
        } catch let error as TradingSnapshotError {
            throw error
        } catch {
            throw TradingSnapshotError.invalidJSON
        }
        guard snapshot.schema == TradingSnapshotDocument.schemaIdentifier else {
            throw TradingSnapshotError.unknownSchema(snapshot.schema)
        }
        guard snapshot.version == TradingSnapshotDocument.currentVersion else {
            throw TradingSnapshotError.unsupportedVersion(snapshot.version)
        }
        return DecodedTradingSnapshot(
            document: snapshot,
            source: .canonical,
            accountIdentityVerified: true
        )
    }

    private static func decodeLegacy(_ data: Data) throws -> DecodedTradingSnapshot {
        let legacy: LegacySnapshot
        do {
            legacy = try JSONDecoder().decode(LegacySnapshot.self, from: data)
        } catch {
            throw TradingSnapshotError.invalidJSON
        }
        guard legacy.version == 1 else {
            throw TradingSnapshotError.unsupportedVersion(legacy.version)
        }
        guard let environment = Trading212Environment(rawValue: legacy.environment.lowercased()) else {
            throw TradingSnapshotError.invalidEnvironment(legacy.environment)
        }
        guard let capturedAt = parseISO8601(legacy.savedAt) else {
            throw TradingSnapshotError.legacyMissingField("saved_at")
        }

        let accountCurrency = legacy.accountCurrency.uppercased()
        let pieByTicker = Dictionary(
            legacy.piesSkipped.map { ($0.ticker, $0.quantityInPies) },
            uniquingKeysWith: { $0 + $1 }
        )
        let allHavePositiveWeights = !legacy.holdings.isEmpty
            && legacy.holdings.allSatisfy { ($0.weight ?? 0) > 0 }
        let bases = legacy.holdings.map { holding in
            allHavePositiveWeights ? holding.weight! : max(0, holding.value ?? 0)
        }
        let basisTotal = bases.reduce(Decimal.zero, +)

        var positions = legacy.holdings.enumerated().map { index, holding in
            let sellable = holding.quantity ?? 0
            let pie = pieByTicker[holding.ticker] ?? 0
            return TradingSnapshotDocument.Position(
                ticker: holding.ticker,
                name: holding.name ?? "",
                instrumentCurrency: (holding.currency ?? accountCurrency).uppercased(),
                quantity: sellable + pie,
                sellableQuantity: sellable,
                pieQuantity: pie,
                nativePrice: nil,
                accountPricePerShare: holding.price ?? 0,
                sellableAccountValue: holding.value ?? 0,
                sellableWeight: basisTotal > 0 ? bases[index] / basisTotal : 0
            )
        }
        let holdingTickers = Set(legacy.holdings.map(\.ticker))
        positions.append(contentsOf: legacy.piesSkipped.filter {
            !holdingTickers.contains($0.ticker)
        }.map { pie in
            return TradingSnapshotDocument.Position(
                ticker: pie.ticker,
                name: "",
                instrumentCurrency: accountCurrency,
                quantity: pie.quantityInPies,
                sellableQuantity: 0,
                pieQuantity: pie.quantityInPies,
                nativePrice: nil,
                accountPricePerShare: 0,
                sellableAccountValue: 0,
                sellableWeight: 0
            )
        })

        let sellablePositionsValue = positions.reduce(Decimal.zero) {
            $0 + $1.sellableAccountValue
        }
        let snapshot = TradingSnapshotDocument(
            kind: .preSale,
            capturedAt: capturedAt,
            environment: environment,
            account: .init(id: "", currency: accountCurrency),
            totals: .init(
                accountValue: legacy.totalValue,
                freeCash: 0,
                sellablePositionsValue: sellablePositionsValue
            ),
            positions: positions
        )
        return DecodedTradingSnapshot(
            document: snapshot,
            source: .legacyAndonV1,
            accountIdentityVerified: false
        )
    }

    private static func validate(
        _ snapshot: TradingSnapshotDocument,
        allowMissingAccountID: Bool
    ) throws {
        guard snapshot.schema == TradingSnapshotDocument.schemaIdentifier else {
            throw TradingSnapshotError.unknownSchema(snapshot.schema)
        }
        guard snapshot.version == TradingSnapshotDocument.currentVersion else {
            throw TradingSnapshotError.unsupportedVersion(snapshot.version)
        }
        if !allowMissingAccountID,
           snapshot.account.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TradingSnapshotError.emptyAccountID
        }
        guard isCurrencyCode(snapshot.account.currency) else {
            throw TradingSnapshotError.invalidCurrency(
                field: "account.currency",
                value: snapshot.account.currency
            )
        }
        let totalValues: [(String, Decimal)] = [
            ("accountValue", snapshot.totals.accountValue),
            ("freeCash", snapshot.totals.freeCash),
            ("sellablePositionsValue", snapshot.totals.sellablePositionsValue),
        ]
        for (field, value) in totalValues where !value.isFinite {
            throw TradingSnapshotError.invalidDecimal(field: field)
        }
        for (field, value) in totalValues where value < 0 {
            throw TradingSnapshotError.negativeValue(field: field, ticker: nil)
        }

        var tickers = Set<String>()
        var positionValueSum: Decimal = 0
        for position in snapshot.positions {
            let ticker = position.ticker.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !ticker.isEmpty else { throw TradingSnapshotError.emptyTicker }
            guard tickers.insert(ticker).inserted else {
                throw TradingSnapshotError.duplicateTicker(ticker)
            }
            guard isCurrencyCode(position.instrumentCurrency) else {
                throw TradingSnapshotError.invalidCurrency(
                    field: "positions.\(ticker).instrumentCurrency",
                    value: position.instrumentCurrency
                )
            }
            let nonNegative: [(String, Decimal)] = [
                ("quantity", position.quantity),
                ("sellableQuantity", position.sellableQuantity),
                ("pieQuantity", position.pieQuantity),
                ("accountPricePerShare", position.accountPricePerShare),
                ("sellableAccountValue", position.sellableAccountValue),
                ("sellableWeight", position.sellableWeight),
            ]
            for (field, value) in nonNegative where value < 0 {
                throw TradingSnapshotError.negativeValue(field: field, ticker: ticker)
            }
            for (field, value) in nonNegative where !value.isFinite {
                throw TradingSnapshotError.invalidDecimal(field: "positions.\(ticker).\(field)")
            }
            if let nativePrice = position.nativePrice, nativePrice < 0 {
                throw TradingSnapshotError.negativeValue(field: "nativePrice", ticker: ticker)
            }
            if let nativePrice = position.nativePrice, !nativePrice.isFinite {
                throw TradingSnapshotError.invalidDecimal(field: "positions.\(ticker).nativePrice")
            }
            guard position.sellableQuantity <= position.quantity,
                  position.pieQuantity <= position.quantity,
                  position.sellableQuantity + position.pieQuantity <= position.quantity else {
                throw TradingSnapshotError.invalidQuantityRelationship(ticker)
            }
            guard position.sellableWeight <= 1 else {
                throw TradingSnapshotError.weightExceedsOne(ticker)
            }
            if position.sellableQuantity > 0 {
                guard position.accountPricePerShare > 0 else {
                    throw TradingSnapshotError.nonPositivePrice(ticker)
                }
                guard position.sellableAccountValue > 0 else {
                    throw TradingSnapshotError.inconsistentPositionValue(ticker)
                }
                guard position.sellableWeight > 0 else {
                    throw TradingSnapshotError.nonPositiveWeight(ticker)
                }
            }
            let expectedValue = position.sellableQuantity * position.accountPricePerShare
            guard approximatelyEqual(expectedValue, position.sellableAccountValue) else {
                throw TradingSnapshotError.inconsistentPositionValue(ticker)
            }
            positionValueSum += position.sellableAccountValue
        }

        // A user may delete positions to exclude them from buy-back, leaving
        // the original totals and weights in place. Therefore sums may be lower
        // than the declared total, but can never exceed it.
        guard positionValueSum <= snapshot.totals.sellablePositionsValue
                + tolerance(for: snapshot.totals.sellablePositionsValue) else {
            throw TradingSnapshotError.inconsistentTotals("sellablePositionsValue")
        }
        guard snapshot.totals.freeCash <= snapshot.totals.accountValue
                + tolerance(for: snapshot.totals.accountValue),
              snapshot.totals.sellablePositionsValue <= snapshot.totals.accountValue
                + tolerance(for: snapshot.totals.accountValue) else {
            throw TradingSnapshotError.inconsistentTotals("accountValue")
        }
        if snapshot.totals.sellablePositionsValue > 0 {
            for position in snapshot.positions {
                let expectedWeight = position.sellableAccountValue
                    / snapshot.totals.sellablePositionsValue
                guard approximatelyEqual(
                    expectedWeight,
                    position.sellableWeight,
                    absoluteFloor: Decimal(string: "0.000001")!,
                    relative: Decimal(string: "0.00001")!
                ) else {
                    throw TradingSnapshotError.inconsistentWeight(position.ticker)
                }
            }
        }
    }

    private static func isCurrencyCode(_ value: String) -> Bool {
        value.count == 3
            && value == value.uppercased()
            && value.unicodeScalars.allSatisfy {
                (UnicodeScalar("A").value...UnicodeScalar("Z").value).contains($0.value)
            }
    }

    private static func tolerance(
        for value: Decimal,
        absoluteFloor: Decimal = Decimal(string: "0.01")!,
        relative: Decimal = Decimal(string: "0.001")!
    ) -> Decimal {
        max(absoluteFloor, abs(value) * relative)
    }

    private static func approximatelyEqual(
        _ lhs: Decimal,
        _ rhs: Decimal,
        absoluteFloor: Decimal = Decimal(string: "0.01")!,
        relative: Decimal = Decimal(string: "0.001")!
    ) -> Bool {
        abs(lhs - rhs) <= max(
            absoluteFloor,
            max(abs(lhs), abs(rhs)) * relative
        )
    }

    private static func makeISO8601Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    private static func parseISO8601(_ string: String) -> Date? {
        if let date = makeISO8601Formatter().date(from: string) { return date }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

public typealias PortfolioSnapshotV1 = TradingSnapshotDocument
public typealias SnapshotCodec = TradingSnapshotCodec

private struct LegacySnapshot: Decodable {
    let version: Int
    let savedAt: String
    let environment: String
    let accountCurrency: String
    let totalValue: Decimal
    let holdings: [LegacyHolding]
    let piesSkipped: [LegacyPie]

    private enum CodingKeys: String, CodingKey {
        case version, environment, holdings
        case savedAt = "saved_at"
        case accountCurrency = "account_currency"
        case totalValue = "total_value"
        case piesSkipped = "pies_skipped"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        savedAt = try values.decode(String.self, forKey: .savedAt)
        environment = try values.decode(String.self, forKey: .environment)
        accountCurrency = try values.decode(String.self, forKey: .accountCurrency)
        totalValue = try values.decodeFlexibleDecimal(forKey: .totalValue)
        holdings = try values.decode([LegacyHolding].self, forKey: .holdings)
        piesSkipped = (try? values.decode([LegacyPie].self, forKey: .piesSkipped)) ?? []
    }
}

private struct LegacyHolding: Decodable {
    let ticker: String
    let name: String?
    let currency: String?
    let quantity: Decimal?
    let price: Decimal?
    let value: Decimal?
    let weight: Decimal?

    private enum CodingKeys: String, CodingKey {
        case ticker, name, currency, quantity, price, value, weight
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        ticker = try values.decode(String.self, forKey: .ticker)
        name = try values.decodeIfPresent(String.self, forKey: .name)
        currency = try values.decodeIfPresent(String.self, forKey: .currency)
        quantity = try values.decodeFlexibleDecimalIfPresent(forKey: .quantity)
        price = try values.decodeFlexibleDecimalIfPresent(forKey: .price)
        value = try values.decodeFlexibleDecimalIfPresent(forKey: .value)
        weight = try values.decodeFlexibleDecimalIfPresent(forKey: .weight)
    }
}

private struct LegacyPie: Decodable {
    let ticker: String
    let quantityInPies: Decimal

    private enum CodingKeys: String, CodingKey { case ticker, quantityInPies }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        ticker = try values.decode(String.self, forKey: .ticker)
        quantityInPies = try values.decodeFlexibleDecimal(forKey: .quantityInPies)
    }
}

private extension KeyedDecodingContainer {
    func decodeDecimalString(forKey key: Key) throws -> Decimal {
        let string = try decode(String.self, forKey: key)
        guard let decimal = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")),
              decimal.isFinite else {
            throw TradingSnapshotError.invalidDecimal(field: key.stringValue)
        }
        return decimal
    }

    func decodeDecimalStringIfPresent(forKey key: Key) throws -> Decimal? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return try decodeDecimalString(forKey: key)
    }

    func decodeFlexibleDecimal(forKey key: Key) throws -> Decimal {
        if let decimal = try? decode(Decimal.self, forKey: key), decimal.isFinite {
            return decimal
        }
        if let string = try? decode(String.self, forKey: key),
           let decimal = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")),
           decimal.isFinite {
            return decimal
        }
        throw TradingSnapshotError.invalidDecimal(field: key.stringValue)
    }

    func decodeFlexibleDecimalIfPresent(forKey key: Key) throws -> Decimal? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return try decodeFlexibleDecimal(forKey: key)
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeDecimalString(_ decimal: Decimal, forKey key: Key) throws {
        try encode(DecimalMath.string(decimal), forKey: key)
    }

    mutating func encodeDecimalStringIfPresent(_ decimal: Decimal?, forKey key: Key) throws {
        guard let decimal else { return }
        try encodeDecimalString(decimal, forKey: key)
    }
}

private extension Decimal {
    var isFinite: Bool {
        let value = NSDecimalNumber(decimal: self)
        return value != .notANumber
    }
}
