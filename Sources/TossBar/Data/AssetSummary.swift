import Foundation

/// Holdings converted to KRW.
///
/// The API splits amounts by currency (`krw`, `usd`), so the USD part is converted at the
/// USD/KRW base rate and added. Rates come from the API as is, because the API already
/// computes them on the KRW-converted portfolio.
struct AssetSummary {
    let overview: HoldingsOverview
    let usdKrw: Decimal?

    var hasUSD: Bool {
        overview.items.contains { $0.currency == .usd }
            || (overview.totalPurchaseAmount.usd.map { $0.value != 0 } ?? false)
    }

    /// The KRW total. nil while a USD part exists but the rate is still unknown.
    func krw(_ amounts: CurrencyAmounts) -> Decimal? {
        let usd = amounts.usd?.value ?? 0
        if usd == 0 { return amounts.krw.value }
        guard let usdKrw else { return nil }
        return amounts.krw.value + usd * usdKrw
    }

    func krw(_ value: Decimal, currency: Currency) -> Decimal? {
        switch currency {
        case .usd: return usdKrw.map { value * $0 }
        default: return value
        }
    }

    var purchase: Decimal? { krw(overview.totalPurchaseAmount) }
    var marketValue: Decimal? { krw(overview.marketValue.amount) }
    var marketValueAfterCost: Decimal? { krw(overview.marketValue.amountAfterCost) }

    var profit: Decimal? { krw(overview.profitLoss.amount) }
    var profitRate: Decimal { overview.profitLoss.rate.value }

    var dailyProfit: Decimal? { krw(overview.dailyProfitLoss.amount) }
    var dailyRate: Decimal { overview.dailyProfitLoss.rate.value }

    /// (profit, rate) shown in the menu bar for an item.
    func headline(for config: AssetItemConfig) -> (amount: Decimal?, rate: Decimal) {
        switch config.mode {
        case .total: return (profit, profitRate)
        case .daily: return (dailyProfit, dailyRate)
        }
    }

    /// A holding's share of the portfolio, by KRW-converted market value.
    func weight(of item: HoldingItem) -> Decimal? {
        guard let total = marketValue, total != 0,
              let value = krw(item.marketValue.amount.value, currency: item.currency) else { return nil }
        return value / total
    }
}
