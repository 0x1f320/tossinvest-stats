import Foundation
import Testing
@testable import TossBar

@Suite("Stock item config")
struct StockItemConfigTests {
    @Test func decodesConfigSavedBeforeDisplayCurrency() throws {
        let json = #"[{"id": "8A0F5D61-2F3B-4C64-9D4B-0B1B7B3C7E10", "kind": {"stock": {"_0": {"symbol": "AAPL", "showName": false, "showChange": true}}}}]"#
        let items = try JSONDecoder().decode([MenuItemConfig].self, from: Data(json.utf8))
        guard case .stock(let config) = items.first?.kind else {
            Issue.record("expected a stock item")
            return
        }
        #expect(config.symbol == "AAPL")
        #expect(config.showName == false)
        #expect(config.displayCurrency == .native)
    }

    @Test func roundTrips() throws {
        let item = MenuItemConfig(kind: .stock(StockItemConfig(symbol: "TSLA", displayName: "테슬라", displayCurrency: .krw)))
        let decoded = try JSONDecoder().decode(MenuItemConfig.self, from: JSONEncoder().encode(item))
        #expect(decoded == item)
    }
}

@Suite("Price conversion")
struct PriceConversionTests {
    @Test func usStockInKRW() {
        let conv = PriceConversion.make(native: .usd, display: .krw, usdKrw: 1375)
        #expect(conv.currency == .krw)
        #expect(conv.isConverted)
        #expect(conv.apply(Decimal(string: "178.5")!) == Decimal(string: "245437.5")!)
        #expect(Fmt.priceWithUnit(conv.apply(Decimal(string: "178.5")!), conv.currency) == "245,438원")
    }

    @Test func staysInDollarsUntilRateArrives() {
        let conv = PriceConversion.make(native: .usd, display: .krw, usdKrw: nil)
        #expect(conv.currency == .usd)
        #expect(!conv.isConverted)
    }

    @Test func domesticStockIsNeverConverted() {
        let conv = PriceConversion.make(native: .krw, display: .krw, usdKrw: 1375)
        #expect(conv.currency == .krw)
        #expect(conv.apply(72000) == 72000)
    }
}
