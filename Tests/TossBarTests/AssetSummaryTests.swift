import Foundation
import Testing
@testable import TossBar

@Suite("Asset summary")
struct AssetSummaryTests {
    private func overview() throws -> HoldingsOverview {
        try TossAPIClient.makeDecoder().decode(HoldingsOverview.self, from: Data(Fixtures.holdingsJSON.utf8))
    }

    @Test func totalProfitConvertsUSDPart() throws {
        let summary = AssetSummary(overview: try overview(), usdKrw: 1375)
        // 700,000 + 232 × 1,375
        #expect(summary.profit(afterCost: false) == 1_019_000)
        let headline = summary.headline(for: AssetItemConfig())
        #expect("\(Fmt.krwProfit(headline.amount!)) (\(Fmt.percent(ratio: headline.rate)))" == "+1,019,000₩ (+11.79%)")
    }

    @Test func dailyMode() throws {
        let summary = AssetSummary(overview: try overview(), usdKrw: 1375)
        let headline = summary.headline(for: AssetItemConfig(mode: .daily))
        // -50,000 + 12 × 1,375
        #expect(headline.amount == -33_500)
        #expect(Fmt.percent(ratio: headline.rate) == "-0.41%")
    }

    @Test func totalsWaitForTheRate() throws {
        let summary = AssetSummary(overview: try overview(), usdKrw: nil)
        #expect(summary.hasUSD)
        #expect(summary.profit(afterCost: false) == nil)
        #expect(summary.marketValue == nil)
    }

    @Test func afterCostBasis() throws {
        let summary = AssetSummary(overview: try overview(), usdKrw: 1375)
        let headline = summary.headline(for: AssetItemConfig(afterCost: true))
        // 680,000 + 123.52 × 1,375
        #expect(headline.amount == 849_840)
        #expect("\(Fmt.krwProfit(headline.amount!)) (\(Fmt.percent(ratio: headline.rate)))" == "+849,840₩ (+9.83%)")
    }

    @Test func dailyModeIgnoresAfterCost() throws {
        let summary = AssetSummary(overview: try overview(), usdKrw: 1375)
        let raw = summary.headline(for: AssetItemConfig(mode: .daily))
        let after = summary.headline(for: AssetItemConfig(mode: .daily, afterCost: true))
        #expect(raw.amount == after.amount)
        #expect(!AssetItemConfig(mode: .daily, afterCost: true).usesAfterCost)
    }

    @Test func holdingProfitBasis() throws {
        let item = try overview().items[1]
        #expect(item.profit(afterCost: false).amount == 232)
        #expect(item.profit(afterCost: true).amount == Decimal(string: "123.52")!)
    }

    @Test func purchaseAndMarketValue() throws {
        let summary = AssetSummary(overview: try overview(), usdKrw: 1375)
        #expect(summary.purchase == 6_375_000)
        #expect(summary.marketValue == 7_394_000)
    }
}

@Suite("Holding weights")
struct HoldingWeightTests {
    @Test func weightsUseKRWValueAndSumToOne() throws {
        let overview = try TossAPIClient.makeDecoder().decode(HoldingsOverview.self, from: Data(Fixtures.holdingsJSON.utf8))
        let summary = AssetSummary(overview: overview, usdKrw: 1375)
        let weights = overview.items.compactMap { summary.weight(of: $0) }
        #expect(weights.count == 2)
        // 5,700,000 / 7,394,000 and 1,232 × 1,375 / 7,394,000
        #expect(Fmt.percent(ratio: weights[0], signed: false) == "77.09%")
        #expect(Fmt.percent(ratio: weights[1], signed: false) == "22.91%")
        #expect(abs((weights[0] + weights[1]).double - 1) < 1e-9)
    }
}

@Suite("Asset item config")
struct AssetItemConfigTests {
    @Test func decodesConfigSavedBeforeAfterCost() throws {
        let json = #"{"kind": {"asset": {"_0": {"label": "💰", "mode": "daily"}}}, "id": "1E7D6F6B-6C4C-4B4E-8E0C-5A2B8D3B1A11"}"#
        let item = try JSONDecoder().decode(MenuItemConfig.self, from: Data(json.utf8))
        guard case .asset(let config) = item.kind else {
            Issue.record("expected an asset item")
            return
        }
        #expect(config.label == "💰")
        #expect(config.mode == .daily)
        #expect(config.accountSeq == nil)
        #expect(config.afterCost == false)
    }
}
