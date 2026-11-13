import SwiftUI

/// A light Path-based sparkline. Cheaper than Swift Charts when a list draws dozens of them.
struct Sparkline: View {
    let values: [Double]
    var color: Color

    var body: some View {
        GeometryReader { geo in
            if values.count >= 2, let minV = values.min(), let maxV = values.max() {
                let span = max(maxV - minV, .ulpOfOne)
                let stepX = geo.size.width / CGFloat(values.count - 1)
                let point: (Int) -> CGPoint = { index in
                    CGPoint(
                        x: CGFloat(index) * stepX,
                        y: geo.size.height - CGFloat((values[index] - minV) / span) * geo.size.height
                    )
                }
                ZStack {
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: geo.size.height))
                        for index in values.indices { path.addLine(to: point(index)) }
                        path.addLine(to: CGPoint(x: geo.size.width, y: geo.size.height))
                        path.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [color.opacity(0.22), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    Path { path in
                        path.move(to: point(0))
                        for index in values.indices.dropFirst() { path.addLine(to: point(index)) }
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
                }
            } else {
                Rectangle().fill(Color.secondary.opacity(0.08)).clipShape(RoundedRectangle(cornerRadius: 3))
            }
        }
    }
}

struct StatCell: View {
    let title: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(.callout, design: .rounded).monospacedDigit()).foregroundStyle(valueColor)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shared popover footer: last update time or error, refresh, and the item menu.
struct PopoverFooter: View {
    let itemID: UUID
    let env: AppEnvironment
    @ObservedObject var data: MarketDataService

    init(itemID: UUID, env: AppEnvironment) {
        self.itemID = itemID
        self.env = env
        self.data = env.data
    }

    var body: some View {
        HStack(spacing: 8) {
            if let error = data.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .help(error)
            } else if let updated = data.lastUpdated {
                Text("업데이트 \(Fmt.time.string(from: updated))").foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if data.isRefreshing {
                ProgressView().controlSize(.mini)
            }
            Button {
                env.data.refreshSoon()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("새로고침")
            Menu {
                Button("이 항목 편집…") { env.editItem(itemID) }
                Button("설정…") { env.openSettings() }
                Divider()
                Button("이 항목 삭제", role: .destructive) { env.store.remove(itemID) }
                Divider()
                Button("TossBar 종료") { env.quit() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .font(.caption)
    }
}
