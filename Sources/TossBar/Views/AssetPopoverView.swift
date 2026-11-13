import SwiftUI

/// Popover for an asset item: account summary, then each holding with its price,
/// trend and how its numbers are calculated.
struct AssetPopoverView: View {
    let itemID: UUID
    let env: AppEnvironment
    @ObservedObject private var data: MarketDataService
    @ObservedObject private var store: ItemStore

    @AppStorage("assetSort") private var sortRaw = HoldingSort.value.rawValue
    @State private var expanded: Set<String> = []
    @State private var sparklines: [String: [Double]] = [:]

    init(itemID: UUID, env: AppEnvironment) {
        self.itemID = itemID
        self.env = env
        self.data = env.data
        self.store = env.store
    }

    private var config: AssetItemConfig? {
        if case .asset(let config) = store.item(itemID)?.kind { return config }
        return nil
    }

    /// Switches the profit basis from the popover. The menu bar follows.
    private func setAfterCost(_ value: Bool) {
        guard var config else { return }
        config.afterCost = value
        store.upsert(MenuItemConfig(id: itemID, kind: .asset(config)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let config {
                if let seq = data.accountSeq(for: config), let overview = data.holdings[seq] {
                    let summary = AssetSummary(overview: overview, usdKrw: data.usdKrwRate)
                    header(config: config, seq: seq, summary: summary)
                    Divider()
                    holdingsList(summary: summary, afterCost: config.usesAfterCost)
                } else {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text(data.errorMessage ?? "보유 주식을 불러오는 중…")
                            .font(.callout).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                }
            } else {
                Text("삭제된 항목입니다.").foregroundStyle(.secondary)
            }
            Divider()
            PopoverFooter(itemID: itemID, env: env)
        }
        .padding(14)
        .frame(width: 440)
        .task(id: holdingSymbols) { await loadSparklines() }
    }

    private var holdingSymbols: [String] {
        guard let config, let seq = data.accountSeq(for: config) else { return [] }
        return data.holdings[seq]?.items.map(\.symbol) ?? []
    }

    private func loadSparklines() async {
        for symbol in holdingSymbols {
            if let cached = data.cachedSparkline(symbol: symbol) { sparklines[symbol] = cached }
        }
        await withTaskGroup(of: (String, [Double]?).self) { group in
            for symbol in holdingSymbols where sparklines[symbol] == nil {
                group.addTask { @MainActor in (symbol, await data.sparkline(symbol: symbol)) }
            }
            for await (symbol, values) in group {
                if let values { sparklines[symbol] = values }
            }
        }
    }

    // MARK: Header

    @ViewBuilder
    private func header(config: AssetItemConfig, seq: Int64, summary: AssetSummary) -> some View {
        let account = data.accounts.first { $0.accountSeq == seq }
        let headline = summary.headline(for: config)
        let trend = Trend(headline.amount ?? headline.rate)

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(config.label.nilIfBlank ?? "내 자산").font(.headline)
                Spacer()
                Text("계좌 \(account?.maskedNumber ?? String(seq))").font(.caption).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(config.mode == .total ? (config.afterCost ? "총 손익 · 수수료·세금 제외" : "총 손익 · 원본") : "일간 손익")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    if config.mode == .total {
                        Picker("수익 기준", selection: Binding(get: { config.afterCost }, set: { setAfterCost($0) })) {
                            Text("원본").tag(false)
                            Text("수수료·세금 제외").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                        .controlSize(.small)
                        .help("메뉴바와 종목별 손익에 쓸 수익 기준")
                    }
                }
                Text("\(headline.amount.map(Fmt.krwProfit) ?? "…") (\(Fmt.percent(ratio: headline.rate)))")
                    .font(.system(size: 22, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(trend.color)
            }
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    StatCell(title: "평가금액", value: summary.marketValue.map { Fmt.number($0) + "원" } ?? "…")
                    StatCell(title: "투자원금", value: summary.purchase.map { Fmt.number($0) + "원" } ?? "…")
                    // The mode not shown in the headline, for comparison.
                    if config.mode == .total {
                        let daily = summary.dailyProfit
                        StatCell(title: "일간 손익",
                                 value: "\(daily.map(Fmt.krwProfit) ?? "…") (\(Fmt.percent(ratio: summary.dailyRate)))",
                                 valueColor: Trend(daily ?? summary.dailyRate).color)
                    } else {
                        let total = summary.profit(afterCost: false)
                        StatCell(title: "총 손익",
                                 value: "\(total.map(Fmt.krwProfit) ?? "…") (\(Fmt.percent(ratio: summary.profitRate(afterCost: false))))",
                                 valueColor: Trend(total ?? 0).color)
                    }
                }
                GridRow {
                    // The basis not shown in the headline, for comparison.
                    let otherIsAfterCost = !config.usesAfterCost
                    let other = summary.profit(afterCost: otherIsAfterCost)
                    StatCell(title: "세후 평가금액", value: summary.marketValueAfterCost.map { Fmt.number($0) + "원" } ?? "…")
                    StatCell(title: otherIsAfterCost ? "수수료·세금 제외 손익" : "원본 손익",
                             value: "\(other.map(Fmt.krwProfit) ?? "…") (\(Fmt.percent(ratio: summary.profitRate(afterCost: otherIsAfterCost))))",
                             valueColor: Trend(other ?? 0).color)
                    StatCell(title: "보유 종목", value: "\(summary.overview.items.count)개")
                }
            }
            if summary.hasUSD {
                usdBreakdown(summary, afterCost: config.usesAfterCost)
            }
        }
    }

    /// Domestic and US totals in their own currencies, with the rate used to combine them.
    @ViewBuilder
    private func usdBreakdown(_ summary: AssetSummary, afterCost: Bool) -> some View {
        let o = summary.overview
        let pl = afterCost ? o.profitLoss.amountAfterCost : o.profitLoss.amount
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("통화별").foregroundStyle(.secondary)
                Spacer()
                if let fx = data.usdKrw {
                    Text("USD/KRW 매매기준율 \(Fmt.number(fx.midRate.value, fraction: 2))")
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("국내").frame(width: 32, alignment: .leading)
                Text("평가 \(Fmt.number(o.marketValue.amount.krw.value))원")
                Spacer()
                Text(Fmt.signedAmount(pl.krw.value, .krw))
                    .foregroundStyle(Trend(pl.krw.value).color)
            }
            if let usdValue = o.marketValue.amount.usd?.value, let usdPL = pl.usd?.value {
                HStack {
                    Text("해외").frame(width: 32, alignment: .leading)
                    Text("평가 $\(Fmt.number(usdValue, fraction: 2))")
                    Spacer()
                    Text(Fmt.signedAmount(usdPL, .usd)).foregroundStyle(Trend(usdPL).color)
                }
            }
        }
        .font(.caption.monospacedDigit())
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.07)))
    }

    // MARK: Holdings

    @ViewBuilder
    private func holdingsList(summary: AssetSummary, afterCost: Bool) -> some View {
        let items = sorted(summary.overview.items, summary: summary, afterCost: afterCost)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("보유 종목").font(.subheadline.weight(.semibold))
                Spacer()
                Picker("정렬", selection: $sortRaw) {
                    ForEach(HoldingSort.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
                .controlSize(.small)
            }
            if items.isEmpty {
                Text("보유 종목이 없습니다.").font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(items) { item in
                            HoldingRow(
                                item: item,
                                summary: summary,
                                afterCost: afterCost,
                                sparkline: sparklines[item.symbol],
                                isExpanded: expanded.contains(item.symbol)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    if expanded.contains(item.symbol) { expanded.remove(item.symbol) } else { expanded.insert(item.symbol) }
                                }
                            }
                            if item.id != items.last?.id { Divider().opacity(0.5) }
                        }
                    }
                }
                .frame(maxHeight: min(CGFloat(items.count) * 56 + CGFloat(expanded.count) * 110, 380))
            }
        }
    }

    private func sorted(_ items: [HoldingItem], summary: AssetSummary, afterCost: Bool) -> [HoldingItem] {
        let sort = HoldingSort(rawValue: sortRaw) ?? .value
        return items.sorted { a, b in
            switch sort {
            case .value:
                return (summary.krw(a.marketValue.amount.value, currency: a.currency) ?? 0) >
                    (summary.krw(b.marketValue.amount.value, currency: b.currency) ?? 0)
            case .profitRate:
                return a.profit(afterCost: afterCost).rate > b.profit(afterCost: afterCost).rate
            case .dailyRate:
                return a.dailyProfitLoss.rate.value > b.dailyProfitLoss.rate.value
            case .name:
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
        }
    }
}

enum HoldingSort: String, CaseIterable, Identifiable {
    case value, profitRate, dailyRate, name
    var id: String { rawValue }
    var title: String {
        switch self {
        case .value: return "평가금액순"
        case .profitRate: return "수익률순"
        case .dailyRate: return "일간 등락순"
        case .name: return "이름순"
        }
    }
}

/// One holding. Tapping it expands the calculation behind its numbers.
struct HoldingRow: View {
    let item: HoldingItem
    let summary: AssetSummary
    /// Show the holding's profit after fees and taxes.
    let afterCost: Bool
    let sparkline: [Double]?
    let isExpanded: Bool

    var body: some View {
        let c = item.currency
        let profit = item.profit(afterCost: afterCost)
        let plTrend = Trend(profit.amount)
        let dailyTrend = Trend(item.dailyProfitLoss.rate.value)

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name).font(.callout.weight(.medium)).lineLimit(1)
                    HStack(spacing: 4) {
                        Text(Fmt.priceWithUnit(item.lastPrice.value, c))
                        Text("\(dailyTrend.arrow)\(Fmt.percent(ratio: abs(item.dailyProfitLoss.rate.value), signed: false))")
                            .foregroundStyle(dailyTrend.color)
                    }
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Sparkline(values: sparkline ?? [], color: sparklineColor)
                    .frame(width: 64, height: 26)
                    .help("최근 30거래일 종가 추이")

                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.priceWithUnit(item.marketValue.amount.value, c))
                        .font(.callout.monospacedDigit())
                    Text("\(Fmt.signedAmount(profit.amount, c)) (\(Fmt.percent(ratio: profit.rate)))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(plTrend.color)
                }
                .frame(minWidth: 120, alignment: .trailing)
            }
            if isExpanded {
                calculation
                    .transition(.opacity)
            }
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 4)
    }

    private var sparklineColor: Color {
        guard let values = sparkline, let first = values.first, let last = values.last else { return .secondary }
        return Trend(Decimal(last - first)).color
    }

    /// Market value, purchase amount, profit, costs and weight, each with its formula.
    private var calculation: some View {
        let c = item.currency
        let qty = Fmt.quantity(item.quantity.value)
        let tax = item.cost.tax?.value ?? 0
        return Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
            calcRow("평가금액", "\(Fmt.priceWithUnit(item.lastPrice.value, c)) × \(qty)주",
                    Fmt.priceWithUnit(item.marketValue.amount.value, c))
            calcRow("매입금액", "평균 \(Fmt.priceWithUnit(item.averagePurchasePrice.value, c)) × \(qty)주",
                    Fmt.priceWithUnit(item.marketValue.purchaseAmount.value, c))
            calcRow("손익", "평가 − 매입",
                    "\(Fmt.signedAmount(item.profitLoss.amount.value, c)) (\(Fmt.percent(ratio: item.profitLoss.rate.value)))",
                    color: Trend(item.profitLoss.amount.value).color)
            calcRow("비용", "수수료 \(Fmt.priceWithUnit(item.cost.commission.value, c)) + 세금 \(Fmt.priceWithUnit(tax, c))",
                    "세후 \(Fmt.signedAmount(item.profitLoss.amountAfterCost.value, c)) (\(Fmt.percent(ratio: item.profitLoss.rateAfterCost.value)))",
                    color: Trend(item.profitLoss.amountAfterCost.value).color)
            calcRow("일간", "전일 대비",
                    "\(Fmt.signedAmount(item.dailyProfitLoss.amount.value, c)) (\(Fmt.percent(ratio: item.dailyProfitLoss.rate.value)))",
                    color: Trend(item.dailyProfitLoss.amount.value).color)
            if c == .usd, let krwValue = summary.krw(item.marketValue.amount.value, currency: .usd) {
                calcRow("원화 환산", "평가 × 매매기준율", "≈ \(Fmt.number(krwValue))원")
            }
            if let weight = summary.weight(of: item) {
                calcRow("비중", "원화 환산 평가금액 기준", Fmt.percent(ratio: weight, signed: false))
            }
        }
        .font(.caption.monospacedDigit())
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.07)))
    }

    private func calcRow(_ title: String, _ formula: String, _ result: String, color: Color = .primary) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(formula).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            Text(result).foregroundStyle(color).gridColumnAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}
