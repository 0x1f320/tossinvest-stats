import Charts
import SwiftUI

/// Popover for a stock item: current price and a recent price chart.
struct StockPopoverView: View {
    let itemID: UUID
    let env: AppEnvironment
    @ObservedObject private var data: MarketDataService
    @ObservedObject private var store: ItemStore

    /// The chosen range is remembered per item.
    @AppStorage private var rangeRaw: String
    @State private var candles: [Candle] = []
    @State private var isLoading = false
    @State private var chartError: String?
    @State private var selectedDate: Date?

    init(itemID: UUID, env: AppEnvironment) {
        self.itemID = itemID
        self.env = env
        self.data = env.data
        self.store = env.store
        _rangeRaw = AppStorage(wrappedValue: ChartRange.day.rawValue, "chartRange.\(itemID.uuidString)")
    }

    private var range: ChartRange { ChartRange(rawValue: rangeRaw) ?? .day }

    private var config: StockItemConfig? {
        if case .stock(let config) = store.item(itemID)?.kind { return config }
        return nil
    }

    private var conversion: PriceConversion {
        guard let config else { return PriceConversion(factor: 1, currency: .krw, rate: nil) }
        return data.priceConversion(symbol: config.symbol, display: config.displayCurrency)
    }

    /// Currency the popover shows prices in.
    private var currency: Currency { conversion.currency }

    private func setDisplayCurrency(_ value: PriceDisplayCurrency) {
        guard var config else { return }
        config.displayCurrency = value
        store.upsert(MenuItemConfig(id: itemID, kind: .stock(config)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let config {
                header(config)
                Picker("", selection: $rangeRaw) {
                    ForEach(ChartRange.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                chartSection(config)
                stats(config)
            } else {
                Text("삭제된 항목입니다.").foregroundStyle(.secondary)
            }
            Divider()
            PopoverFooter(itemID: itemID, env: env)
        }
        .padding(14)
        .frame(width: 380)
        .task(id: "\(config?.symbol ?? "")|\(rangeRaw)") {
            guard let symbol = config?.symbol else { return }
            // Keep the chart fresh while the popover is open.
            while !Task.isCancelled {
                await loadChart(symbol: symbol)
                let wait: Double = range == .day ? 30 : 300
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }

    // MARK: Header

    @ViewBuilder
    private func header(_ config: StockItemConfig) -> some View {
        let info = data.stockInfo[config.symbol]
        let quote = data.quotes[config.symbol]
        let conv = conversion
        let isUS = data.currency(for: config.symbol) == .usd

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(info?.name ?? config.symbol).font(.headline).lineLimit(1)
                Spacer()
                Text([info?.market, config.symbol].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary)
                if isUS {
                    // US stocks: switch this item's currency right here (the menu bar follows).
                    Picker("표시 통화", selection: Binding(
                        get: { config.displayCurrency },
                        set: { setDisplayCurrency($0) }
                    )) {
                        Text("$").tag(PriceDisplayCurrency.native)
                        Text("₩").tag(PriceDisplayCurrency.krw)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .controlSize(.small)
                    .help("이 항목의 가격 표시 통화")
                }
            }
            if let selected = selectedPoint {
                // Hovering the chart: show the value at that point (already converted).
                Text(Fmt.priceWithUnit(Decimal(selected.value), currency))
                    .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                Text(selected.date, format: range == .day
                     ? .dateTime.hour().minute()
                     : .dateTime.year().month().day())
                    .font(.callout).foregroundStyle(.secondary)
            } else if let quote {
                Text(Fmt.priceWithUnit(conv.apply(quote.lastPrice.value), currency))
                    .font(.system(size: 24, weight: .semibold, design: .rounded).monospacedDigit())
                HStack(spacing: 6) {
                    if let change = data.change(for: config.symbol) {
                        let trend = Trend(change.amount)
                        Text("\(trend.arrow) \(Fmt.signedAmount(conv.apply(change.amount), currency)) (\(Fmt.percent(ratio: change.rate)))")
                            .foregroundStyle(trend.color)
                        Text("전일 대비").foregroundStyle(.secondary)
                    }
                    if range != .day, let periodChange {
                        Text("·").foregroundStyle(.secondary)
                        Text("\(range.title) \(Fmt.percent(ratio: periodChange))")
                            .foregroundStyle(Trend(periodChange).color)
                    }
                }
                .font(.callout.monospacedDigit())
                if let rate = conv.rate {
                    Text("$\(Fmt.number(quote.lastPrice.value, fraction: 2)) × USD/KRW \(Fmt.number(rate, fraction: 2)) (현재 매매기준율) · 등락률은 달러 기준")
                        .font(.caption).foregroundStyle(.secondary)
                } else if isUS, config.displayCurrency == .krw {
                    Text("환율을 불러오는 중이라 달러로 표시합니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(data.symbolErrors[config.symbol] ?? "불러오는 중…")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Chart

    /// In KRW, past prices are converted at today's rate, so the shape matches the USD chart.
    private var points: [ChartPoint] {
        let conv = conversion
        return candles.map { ChartPoint(date: $0.timestamp, value: conv.apply($0.closePrice.double)) }
    }

    /// Dashed reference line: the previous close on 1D, the first close otherwise.
    private var baseline: Double? {
        guard let config else { return nil }
        let raw: Double?
        if range == .day {
            raw = data.daily[config.symbol]?.previous?.closePrice.double ?? candles.first?.openPrice.double
        } else {
            raw = candles.first?.closePrice.double
        }
        return raw.map { conversion.apply($0) }
    }

    private var periodChange: Decimal? {
        guard let first = candles.first?.closePrice.value, first != 0,
              let last = candles.last?.closePrice.value else { return nil }
        return (last - first) / first
    }

    private var selectedPoint: ChartPoint? {
        guard let selectedDate, !points.isEmpty else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    @ViewBuilder
    private func chartSection(_ config: StockItemConfig) -> some View {
        let pts = points
        ZStack {
            if pts.count >= 2 {
                let values = pts.map(\.value) + (baseline.map { [$0] } ?? [])
                let lo = values.min()!, hi = values.max()!
                let pad = max((hi - lo) * 0.08, hi * 0.001)
                let lower = lo - pad, upper = hi + pad
                let lastValue = pts.last!.value
                let color = Trend(Decimal(lastValue - (baseline ?? pts.first!.value))).color

                Chart {
                    ForEach(pts) { point in
                        AreaMark(
                            x: .value("시간", point.date),
                            yStart: .value("하한", lower),
                            yEnd: .value("가격", point.value)
                        )
                        .foregroundStyle(LinearGradient(colors: [color.opacity(0.25), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.linear)

                        LineMark(x: .value("시간", point.date), y: .value("가격", point.value))
                            .foregroundStyle(color)
                            .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.linear)
                    }
                    if let baseline {
                        RuleMark(y: .value("기준", baseline))
                            .foregroundStyle(.secondary.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                    }
                    if let selected = selectedPoint {
                        RuleMark(x: .value("선택", selected.date))
                            .foregroundStyle(.secondary.opacity(0.5))
                        PointMark(x: .value("선택", selected.date), y: .value("가격", selected.value))
                            .foregroundStyle(color)
                            .symbolSize(30)
                    }
                }
                .chartYScale(domain: lower...upper)
                .chartXSelection(value: $selectedDate)
                .chartXAxis {
                    // Explicit formats: the automatic ones overlap at this width.
                    AxisMarks(values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                Text(range == .day ? Fmt.hourMinute.string(from: date) : Fmt.monthDay.string(from: date))
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine().foregroundStyle(.secondary.opacity(0.15))
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(Fmt.price(Decimal(v), currency))
                            }
                        }
                    }
                }
            } else if isLoading {
                ProgressView()
            } else {
                Text(chartError ?? "차트 데이터가 없습니다.")
                    .font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if isLoading && pts.count >= 2 {
                VStack { HStack { Spacer(); ProgressView().controlSize(.small) }; Spacer() }
            }
        }
        .frame(height: 180)
    }

    private func loadChart(symbol: String) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await data.chartCandles(symbol: symbol, range: range)
            candles = result
            chartError = nil
        } catch {
            // Keep showing the last chart if a refresh fails.
            if candles.isEmpty { chartError = error.localizedDescription }
        }
    }

    // MARK: Stats

    @ViewBuilder
    private func stats(_ config: StockItemConfig) -> some View {
        if let snapshot = data.daily[config.symbol] {
            let latest = snapshot.latest
            let conv = conversion
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    StatCell(title: "시가", value: Fmt.price(conv.apply(latest.openPrice.value), currency))
                    StatCell(title: "고가", value: Fmt.price(conv.apply(latest.highPrice.value), currency), valueColor: Trend.up.color)
                    StatCell(title: "저가", value: Fmt.price(conv.apply(latest.lowPrice.value), currency), valueColor: Trend.down.color)
                    StatCell(title: "거래량", value: Fmt.compact(latest.volume.value))
                }
                if let previous = snapshot.previous {
                    GridRow {
                        StatCell(title: "전일 종가", value: Fmt.price(conv.apply(previous.closePrice.value), currency))
                        if let lo = candles.map(\.lowPrice.value).min(), let hi = candles.map(\.highPrice.value).max(), range != .day {
                            StatCell(title: "\(range.title) 최고", value: Fmt.price(conv.apply(hi), currency))
                            StatCell(title: "\(range.title) 최저", value: Fmt.price(conv.apply(lo), currency))
                        } else {
                            StatCell(title: " ", value: " ")
                            StatCell(title: " ", value: " ")
                        }
                        StatCell(title: "기준일", value: latest.timestamp.formatted(.dateTime.month(.defaultDigits).day()))
                    }
                }
            }
        }
    }
}
