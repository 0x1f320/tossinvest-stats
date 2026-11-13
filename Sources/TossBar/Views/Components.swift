import SwiftUI

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
