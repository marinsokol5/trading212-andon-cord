import Foundation

public enum CurrencyDisplay {
    public static func string(_ amount: Decimal, currencyCode: String,
                              style: ValueDisplayStyle = .compactDecimal,
                              separators: SeparatorStyle = .commaDot,
                              locale: Locale = .current) -> String {
        let symbol = currencySymbol(for: currencyCode, locale: locale)
        let magnitude = amount < 0 ? -amount : amount
        let (divisor, suffix) = unit(for: magnitude, style: style)
        let digits = fractionDigits(for: style, hasSuffix: !suffix.isEmpty)
        let number = decimalString(
            magnitude / divisor, minimumFractionDigits: digits,
            maximumFractionDigits: digits, separators: separators, locale: locale)
        return (amount < 0 ? "-" : "") + symbol + number + suffix
    }

    public static func signedString(_ amount: Decimal, currencyCode: String,
                                    style: ValueDisplayStyle = .fullWithCents,
                                    separators: SeparatorStyle = .commaDot,
                                    locale: Locale = .current) -> String {
        (amount < 0 ? "-" : "+") + string(
            amount < 0 ? -amount : amount, currencyCode: currencyCode,
            style: style, separators: separators, locale: locale)
    }

    /// Accepts a fraction (`0.125` = 12.5%).
    public static func percentString(_ fraction: Decimal,
                                     fractionDigits: Int = 2,
                                     explicitSign: Bool = true,
                                     separators: SeparatorStyle = .commaDot,
                                     locale: Locale = .current) -> String {
        let percent = fraction * 100
        let magnitude = percent < 0 ? -percent : percent
        let sign = percent < 0 ? "-" : (explicitSign ? "+" : "")
        return sign + decimalString(
            magnitude, minimumFractionDigits: fractionDigits,
            maximumFractionDigits: fractionDigits,
            separators: separators, locale: locale) + "%"
    }

    public static func decimalString(_ value: Decimal,
                                     minimumFractionDigits: Int = 0,
                                     maximumFractionDigits: Int = 6,
                                     separators: SeparatorStyle = .commaDot,
                                     locale: Locale = .current,
                                     usesGroupingSeparator: Bool = true) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = usesGroupingSeparator
        formatter.groupingSize = 3
        formatter.minimumFractionDigits = minimumFractionDigits
        formatter.maximumFractionDigits = maximumFractionDigits
        formatter.roundingMode = .halfUp
        configure(formatter, separators: separators, locale: locale)
        return formatter.string(from: NSDecimalNumber(decimal: value))
            ?? DecimalCoding.string(value)
    }

    private static func unit(for magnitude: Decimal,
                             style: ValueDisplayStyle) -> (Decimal, String) {
        switch style {
        case .full, .fullWithCents: (1, "")
        case .compact, .compactDecimal:
            switch magnitude {
            case ..<1_000: (1, "")
            case ..<1_000_000: (1_000, "K")
            case ..<1_000_000_000: (1_000_000, "M")
            case ..<1_000_000_000_000: (1_000_000_000, "B")
            default: (1_000_000_000_000, "T")
            }
        }
    }

    private static func fractionDigits(for style: ValueDisplayStyle,
                                       hasSuffix: Bool) -> Int {
        switch style {
        case .compact: 0
        case .compactDecimal: hasSuffix ? 1 : 0
        case .full: 0
        case .fullWithCents: 2
        }
    }

    private static func configure(_ formatter: NumberFormatter,
                                  separators: SeparatorStyle, locale: Locale) {
        switch separators {
        case .commaDot:
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.groupingSeparator = ","
            formatter.decimalSeparator = "."
        case .dotComma:
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.groupingSeparator = "."
            formatter.decimalSeparator = ","
        case .system:
            formatter.locale = locale
        }
    }

    private static func currencySymbol(for currencyCode: String, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = locale
        formatter.currencyCode = currencyCode.uppercased()
        return formatter.currencySymbol ?? currencyCode.uppercased() + " "
    }
}
