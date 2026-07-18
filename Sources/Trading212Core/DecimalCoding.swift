import Foundation

enum DecimalCoding {
    static func decode<K: CodingKey>(_ container: KeyedDecodingContainer<K>,
                                     forKey key: K) throws -> Decimal {
        if let value = try? container.decode(Decimal.self, forKey: key), isFinite(value) {
            return value
        }
        if let string = try? container.decode(String.self, forKey: key),
           let value = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")),
           isFinite(value) {
            return value
        }
        throw DecodingError.typeMismatch(
            Decimal.self,
            DecodingError.Context(codingPath: container.codingPath + [key],
                                  debugDescription: "Expected a finite decimal number or decimal string."))
    }

    static func decodeIfPresent<K: CodingKey>(_ container: KeyedDecodingContainer<K>,
                                              forKey key: K) throws -> Decimal? {
        guard container.contains(key), try !container.decodeNil(forKey: key) else { return nil }
        return try decode(container, forKey: key)
    }

    static func string(_ value: Decimal) -> String {
        var value = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 38, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    private static func isFinite(_ value: Decimal) -> Bool {
        NSDecimalNumber(decimal: value) != .notANumber
    }
}

struct LosslessString: Decodable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let integer = try? container.decode(Int64.self) {
            value = String(integer)
        } else if let decimal = try? container.decode(Decimal.self) {
            value = DecimalCoding.string(decimal)
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                DecodingError.Context(codingPath: decoder.codingPath,
                                      debugDescription: "Expected a string or number."))
        }
    }
}
