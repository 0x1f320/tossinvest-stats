import Foundation

extension Decimal {
    var double: Double { NSDecimalNumber(decimal: self).doubleValue }
}

/// Number formatting for prices, amounts and rates.
/// Grouping is always `,` and rounding is half-up, regardless of the system locale.
enum Fmt {
    private static func formatter(min: Int, max: Int, signed: Bool) -> NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US_POSIX")
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        f.groupingSize = 3
        f.minimumFractionDigits = min
        f.maximumFractionDigits = max
        f.roundingMode = .halfUp
        if signed { f.positivePrefix = "+" }
        return f
    }

    /// `signed` adds `+` to positive values. Zero never gets a sign.
    static func number(_ value: Decimal, fraction: Int = 0, maxFraction: Int? = nil, signed: Bool = false) -> String {
        let isZero = value == 0
        let f = formatter(min: fraction, max: maxFraction ?? fraction, signed: signed && !isZero)
        return f.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }

    /// Short price for the menu bar: `72,000` / `$185.70`
    static func price(_ value: Decimal, _ currency: Currency) -> String {
        switch currency {
        case .usd: return "$" + number(value, fraction: 2)
        default: return number(value)
        }
    }

    /// Price with its unit: `72,000원` / `$185.70`
    static func priceWithUnit(_ value: Decimal, _ currency: Currency) -> String {
        switch currency {
        case .usd: return "$" + number(value, fraction: 2)
        default: return number(value) + "원"
        }
    }

    /// Signed amount: `+700,000원` / `-$12.30`
    static func signedAmount(_ value: Decimal, _ currency: Currency) -> String {
        let sign = value > 0 ? "+" : (value < 0 ? "-" : "")
        let magnitude = abs(value)
        switch currency {
        case .usd: return sign + "$" + number(magnitude, fraction: 2)
        default: return sign + number(magnitude) + "원"
        }
    }

    /// A ratio as a percentage: `0.1234` → `+12.34%`
    static func percent(ratio: Decimal, signed: Bool = true) -> String {
        number(ratio * 100, fraction: 2, signed: signed) + "%"
    }

    static func quantity(_ value: Decimal) -> String {
        number(value, fraction: 0, maxFraction: 6)
    }

    /// Large numbers in Korean units: `1.23억`, `45.6만`
    static func compact(_ value: Decimal) -> String {
        let d = value.double
        switch abs(d) {
        case 1_000_000_000_000...: return String(format: "%.2f조", d / 1_000_000_000_000)
        case 100_000_000...: return String(format: "%.2f억", d / 100_000_000)
        case 10_000...: return String(format: "%.1f만", d / 10_000)
        default: return number(value)
        }
    }

    static let hourMinute: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f
    }()

    static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
