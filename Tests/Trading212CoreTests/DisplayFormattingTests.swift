import Foundation
import XCTest
@testable import Trading212Core

final class DisplayFormattingTests: XCTestCase {
    private let locale = Locale(identifier: "en_US")

    private func format(_ value: String, style: ValueDisplayStyle,
                        separators: SeparatorStyle = .commaDot) -> String {
        CurrencyDisplay.string(
            Decimal(string: value)!, currencyCode: "EUR", style: style,
            separators: separators, locale: locale)
    }

    func testCompactFormatting() {
        XCTAssertEqual(format("430", style: .compactDecimal), "€430")
        XCTAssertEqual(format("49900", style: .compactDecimal), "€49.9K")
        XCTAssertEqual(format("2500000000", style: .compactDecimal), "€2.5B")
        XCTAssertEqual(format("50000", style: .compact), "€50K")
    }

    func testFullAndSeparatorFormatting() {
        XCTAssertEqual(format("50000.5", style: .fullWithCents), "€50,000.50")
        XCTAssertEqual(format("50000.5", style: .fullWithCents, separators: .dotComma),
                       "€50.000,50")
        XCTAssertEqual(format("-1250", style: .full), "-€1,250")
    }

    func testSignedAndPercentFormatting() {
        XCTAssertEqual(CurrencyDisplay.signedString(
            12.5, currencyCode: "USD", separators: .commaDot, locale: locale), "+$12.50")
        XCTAssertEqual(CurrencyDisplay.percentString(
            Decimal(string: "0.0131")!, explicitSign: true,
            separators: .commaDot, locale: locale), "+1.31%")
        XCTAssertEqual(CurrencyDisplay.percentString(
            Decimal(string: "-0.125")!, fractionDigits: 1,
            separators: .commaDot, locale: locale), "-12.5%")
    }

    func testDecimalQuantityDoesNotUseBinaryFloatingPoint() {
        XCTAssertEqual(CurrencyDisplay.decimalString(
            Decimal(string: "0.123456789")!, maximumFractionDigits: 9,
            usesGroupingSeparator: false), "0.123456789")
    }
}
