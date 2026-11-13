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
        #expect(summary.profit == 1_019_000)
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
        #expect(summary.profit == nil)
        #expect(summary.marketValue == nil)
    }

    @Test func purchaseAndMarketValue() throws {
        let summary = AssetSummary(overview: try overview(), usdKrw: 1375)
        #expect(summary.purchase == 6_375_000)
        #expect(summary.marketValue == 7_394_000)
    }
}
