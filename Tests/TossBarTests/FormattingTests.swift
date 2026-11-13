import Foundation
import Testing
@testable import TossBar

@Suite("Formatting")
struct FormattingTests {
    @Test func prices() {
        #expect(Fmt.price(72000, .krw) == "72,000")
        #expect(Fmt.price(Decimal(string: "185.7")!, .usd) == "$185.70")
        #expect(Fmt.priceWithUnit(1_234_567, .krw) == "1,234,567원")
        #expect(Fmt.priceWithUnit(Decimal(string: "0.5")!, .usd) == "$0.50")
    }

    @Test func signedAmounts() {
        #expect(Fmt.signedAmount(700_000, .krw) == "+700,000원")
        #expect(Fmt.signedAmount(Decimal(string: "-12.3")!, .usd) == "-$12.30")
        #expect(Fmt.signedAmount(0, .krw) == "0원")
    }

    @Test func percents() {
        #expect(Fmt.percent(ratio: Decimal(string: "0.1179")!) == "+11.79%")
        #expect(Fmt.percent(ratio: Decimal(string: "-0.0041")!) == "-0.41%")
        #expect(Fmt.percent(ratio: 0) == "0.00%")
        #expect(Fmt.percent(ratio: Decimal(string: "0.05")!, signed: false) == "5.00%")
    }

    @Test func roundsHalfUp() {
        #expect(Fmt.number(Decimal(string: "2.5")!) == "3")
        #expect(Fmt.number(Decimal(string: "0.125")!, fraction: 2) == "0.13")
    }

    @Test func compactKoreanUnits() {
        #expect(Fmt.compact(12_345) == "1.2만")
        #expect(Fmt.compact(123_456_789) == "1.23억")
        #expect(Fmt.compact(999) == "999")
    }

    @Test func quantityKeepsFractionalShares() {
        #expect(Fmt.quantity(Decimal(string: "1.5")!) == "1.5")
        #expect(Fmt.quantity(10) == "10")
    }
}

@Suite("Trend")
struct TrendTests {
    @Test func direction() {
        #expect(Trend(1).arrow == "▲")
        #expect(Trend(-1).arrow == "▼")
        #expect(Trend(0).arrow == "–")
    }
}
