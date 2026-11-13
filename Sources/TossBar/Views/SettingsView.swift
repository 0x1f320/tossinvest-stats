import SwiftUI

struct SettingsView: View {
    let env: AppEnvironment
    @AppStorage("settingsTab") private var tab = "items"

    var body: some View {
        TabView(selection: $tab) {
            ItemsSettingsView(env: env)
                .tabItem { Label("항목", systemImage: "menubar.rectangle") }
                .tag("items")
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    CredentialsHelp()
                    GroupBox {
                        CredentialsForm(credentials: env.credentials).padding(6)
                    }
                }
                .padding(20)
            }
            .tabItem { Label("API 연결", systemImage: "key") }
            .tag("api")
            GeneralSettingsView(settings: env.settings, env: env)
                .tabItem { Label("일반", systemImage: "gearshape") }
                .tag("general")
        }
        .frame(width: 580, height: 480)
    }
}

// MARK: - Items

enum EditorTarget: Identifiable {
    case newStock
    case newAsset
    case edit(MenuItemConfig)

    var id: String {
        switch self {
        case .newStock: return "newStock"
        case .newAsset: return "newAsset"
        case .edit(let item): return item.id.uuidString
        }
    }
}

struct ItemsSettingsView: View {
    let env: AppEnvironment
    @ObservedObject private var store: ItemStore
    @ObservedObject private var data: MarketDataService
    @State private var selection: UUID?
    @State private var editor: EditorTarget?

    init(env: AppEnvironment) {
        self.env = env
        self.store = env.store
        self.data = env.data
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("각 항목이 메뉴바 아이템 하나가 됩니다. 메뉴바에서의 위치는 ⌘+드래그나 Thaw·Ice 같은 메뉴바 관리 앱으로 바꿀 수 있습니다.")
                .font(.callout).foregroundStyle(.secondary)

            List(selection: $selection) {
                ForEach(store.items) { item in
                    row(item)
                        .tag(item.id)
                        .contextMenu {
                            Button("편집…") { editor = .edit(item) }
                            Button("삭제", role: .destructive) { store.remove(item.id) }
                        }
                }
                .onDelete { offsets in
                    offsets.map { store.items[$0].id }.forEach(store.remove)
                }
            }
            .listStyle(.bordered(alternatesRowBackgrounds: true))
            .overlay {
                if store.items.isEmpty {
                    Text("아직 항목이 없습니다.\n아래 + 버튼으로 '주가' 또는 '자산' 항목을 추가하세요.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Menu {
                    Button("주가 항목 추가…") { editor = .newStock }
                    Button("자산 항목 추가…") { editor = .newAsset }
                } label: {
                    Label("추가", systemImage: "plus")
                }
                .fixedSize()

                Button {
                    if let selection, let item = store.item(selection) { editor = .edit(item) }
                } label: {
                    Label("편집", systemImage: "pencil")
                }
                .disabled(selection == nil)

                Button(role: .destructive) {
                    if let selection { store.remove(selection) }
                    selection = nil
                } label: {
                    Label("삭제", systemImage: "minus")
                }
                .disabled(selection == nil)
                Spacer()
            }
        }
        .padding(20)
        .onReceive(env.$pendingEdit) { id in
            guard let id, let item = store.item(id) else { return }
            selection = id
            editor = .edit(item)
            env.pendingEdit = nil
        }
        .sheet(item: $editor) { target in
            switch target {
            case .newStock:
                StockItemEditor(env: env, existing: nil) { editor = nil }
            case .newAsset:
                AssetItemEditor(env: env, existing: nil) { editor = nil }
            case .edit(let item):
                switch item.kind {
                case .stock: StockItemEditor(env: env, existing: item) { editor = nil }
                case .asset: AssetItemEditor(env: env, existing: item) { editor = nil }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ item: MenuItemConfig) -> some View {
        HStack(spacing: 10) {
            switch item.kind {
            case .stock(let config):
                Image(systemName: "chart.xyaxis.line").foregroundStyle(.blue).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text("주가 · \(config.displayName?.nilIfBlank ?? data.stockInfo[config.symbol]?.name ?? config.symbol)")
                    Text(stockDetail(config))
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .asset(let config):
                Image(systemName: "wallet.pass").foregroundStyle(.orange).frame(width: 20)
                VStack(alignment: .leading, spacing: 1) {
                    Text("자산" + (config.label.nilIfBlank.map { " · \($0)" } ?? ""))
                    Text(assetDetail(config))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                store.remove(item.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("삭제")
        }
        .padding(.vertical, 3)
    }

    private func stockDetail(_ config: StockItemConfig) -> String {
        [
            config.symbol,
            config.showName ? "이름 표시" : "이름 숨김",
            config.showChange ? "등락률 표시" : "등락률 숨김",
            config.displayCurrency == .krw ? "원화 환산" : nil,
        ].compactMap { $0 }.joined(separator: " · ")
    }

    private func assetDetail(_ config: AssetItemConfig) -> String {
        let account = data.accounts.first { $0.accountSeq == config.accountSeq }?.maskedNumber ?? "기본 계좌"
        return "\(account) · \(config.mode.title)\(config.usesAfterCost ? " · 수수료·세금 제외" : "")"
    }
}

// MARK: - Stock editor

struct StockItemEditor: View {
    let env: AppEnvironment
    let existing: MenuItemConfig?
    var dismiss: () -> Void

    @ObservedObject private var universe: StockUniverse
    @State private var query = ""
    @State private var selectedSymbol: String?
    @State private var selectedName: String?
    @State private var listSelection: String?
    @State private var displayName = ""
    @State private var showName = true
    @State private var showChange = true
    @State private var displayCurrency: PriceDisplayCurrency = .native
    @State private var isValidating = false
    @State private var error: String?

    init(env: AppEnvironment, existing: MenuItemConfig?, dismiss: @escaping () -> Void) {
        self.env = env
        self.existing = existing
        self.dismiss = dismiss
        self.universe = env.universe
        if case .stock(let config)? = existing?.kind {
            _selectedSymbol = State(initialValue: config.symbol)
            _selectedName = State(initialValue: env.data.stockInfo[config.symbol]?.name)
            _displayName = State(initialValue: config.displayName ?? "")
            _showName = State(initialValue: config.showName)
            _showChange = State(initialValue: config.showChange)
            _displayCurrency = State(initialValue: config.displayCurrency)
        }
    }

    private var results: [StockUniverse.Entry] { universe.search(query) }

    /// Whether the chosen stock is a US stock, from the search list or the stock info
    /// already loaded. Otherwise a non-numeric code is taken as a US ticker (Korean codes
    /// are six characters starting with a digit).
    private var selectedIsUS: Bool {
        guard let symbol = selectedSymbol else { return false }
        if let entry = universe.entries.first(where: { $0.symbol == symbol }) { return entry.isUS }
        if let info = env.data.stockInfo[symbol] { return info.currency == .usd }
        return symbol.range(of: "^[0-9][0-9A-Z]{5}$", options: .regularExpression) == nil
    }

    private var originalSymbol: String? {
        if case .stock(let config)? = existing?.kind { return config.symbol }
        return nil
    }

    private var originalName: String? {
        originalSymbol.flatMap { env.data.stockInfo[$0]?.name }
    }

    /// The query itself as a symbol, for stocks missing from the search list.
    private var manualSymbol: String? {
        let q = query.trimmingCharacters(in: .whitespaces).uppercased()
        guard !q.isEmpty, q.range(of: "^[A-Z0-9.\\-]+$", options: .regularExpression) != nil else { return nil }
        return q
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(existing == nil ? "주가 항목 추가" : "주가 항목 편집").font(.title3.weight(.semibold))

            HStack(spacing: 6) {
                Text(existing == nil ? "선택한 종목" : "종목").foregroundStyle(.secondary)
                if let selectedSymbol {
                    Text("\(selectedName ?? selectedSymbol) (\(selectedSymbol))").fontWeight(.medium)
                    if let originalSymbol, originalSymbol != selectedSymbol {
                        Text("← \(originalName ?? originalSymbol)에서 변경").font(.caption).foregroundStyle(.orange)
                    }
                } else {
                    Text("아래에서 검색해 선택하세요").foregroundStyle(.tertiary)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                TextField(existing == nil
                          ? "종목명 또는 코드 검색 (예: 삼성전자, 005930, AAPL)"
                          : "다른 종목으로 바꾸려면 검색 (예: 삼성전자, 005930, AAPL)", text: $query)
                    .textFieldStyle(.roundedBorder)

                Group {
                    if universe.isLoading && universe.entries.isEmpty {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("종목 목록 불러오는 중… (\(universe.loadedMarkets)/\(StockUniverse.markets.count))")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(selection: $listSelection) {
                            if let manual = manualSymbol, !results.contains(where: { $0.symbol == manual }) {
                                HStack {
                                    Image(systemName: "keyboard")
                                    Text("코드로 직접 지정: \(manual)")
                                }
                                .tag(manual)
                            }
                            ForEach(results) { entry in
                                HStack {
                                    Text(entry.name)
                                    Spacer()
                                    Text("\(entry.symbol) · \(entry.market)")
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                                .tag(entry.symbol)
                            }
                        }
                        .listStyle(.bordered)
                    }
                }
                .frame(height: existing == nil ? 200 : 160)
                if let message = universe.errorMessage, universe.entries.isEmpty {
                    Text("종목 목록을 불러오지 못했습니다: \(message)\n코드를 직접 입력해도 지정할 수 있습니다.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }

            Form {
                TextField("메뉴바 표시 이름", text: $displayName, prompt: Text("비우면 종목명 사용"))
                Toggle("메뉴바에 이름 표시", isOn: $showName)
                Toggle("메뉴바에 전일 대비 등락률 표시", isOn: $showChange)
                if selectedIsUS {
                    Picker("가격 표시 통화", selection: $displayCurrency) {
                        ForEach(PriceDisplayCurrency.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Text("원화는 USD/KRW 매매기준율로 환산합니다. 등락률은 달러 기준입니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.columns)

            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("취소", action: dismiss).keyboardShortcut(.cancelAction)
                Button(existing == nil ? "추가" : "저장", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(selectedSymbol == nil || isValidating)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { universe.ensureLoaded() }
        .onChange(of: listSelection) { _, symbol in
            // Clicking empty space clears the list selection; keep the chosen stock.
            guard let symbol else { return }
            selectedSymbol = symbol
            selectedName = results.first { $0.symbol == symbol }?.name
                ?? env.data.stockInfo[symbol]?.name
            error = nil
        }
    }

    private func makeConfig(symbol: String) -> StockItemConfig {
        StockItemConfig(
            symbol: symbol,
            displayName: displayName.nilIfBlank,
            showName: showName,
            showChange: showChange,
            displayCurrency: selectedIsUS ? displayCurrency : .native
        )
    }

    private func save() {
        guard let symbol = selectedSymbol else { return }
        let item = MenuItemConfig(id: existing?.id ?? UUID(), kind: .stock(makeConfig(symbol: symbol)))

        // A newly chosen symbol that isn't in the search list is checked against the API first.
        if symbol != originalSymbol, !universe.entries.contains(where: { $0.symbol == symbol }) {
            isValidating = true
            Task {
                defer { isValidating = false }
                do {
                    let found = try await env.client.stocks([symbol])
                    guard !found.isEmpty else { error = "종목을 찾을 수 없습니다: \(symbol)"; return }
                    env.store.upsert(item)
                    dismiss()
                } catch {
                    self.error = error.localizedDescription
                }
            }
        } else {
            env.store.upsert(item)
            dismiss()
        }
    }
}

// MARK: - Asset editor

struct AssetItemEditor: View {
    let env: AppEnvironment
    let existing: MenuItemConfig?
    var dismiss: () -> Void

    @ObservedObject private var data: MarketDataService
    @State private var label = ""
    @State private var accountSeq: Int64?
    @State private var mode: AssetMode = .total
    @State private var afterCost = false
    @State private var loadingAccounts = false
    @State private var error: String?

    init(env: AppEnvironment, existing: MenuItemConfig?, dismiss: @escaping () -> Void) {
        self.env = env
        self.existing = existing
        self.dismiss = dismiss
        self.data = env.data
        if case .asset(let config)? = existing?.kind {
            _label = State(initialValue: config.label)
            _accountSeq = State(initialValue: config.accountSeq)
            _mode = State(initialValue: config.mode)
            _afterCost = State(initialValue: config.afterCost)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(existing == nil ? "자산 항목 추가" : "자산 항목 편집").font(.title3.weight(.semibold))
            Text("보유 종목 기준 손익을 메뉴바에 '{수익}₩ ({수익률}%)' 형식으로 표시합니다. 해외 주식 손익은 매매기준율로 원화 환산합니다.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Form {
                TextField("라벨", text: $label, prompt: Text("선택 (예: 💰, 주식)"))
                HStack {
                    Picker("계좌", selection: $accountSeq) {
                        Text("기본 계좌 (첫 번째)").tag(Int64?.none)
                        ForEach(data.accounts) { account in
                            Text("\(account.maskedNumber) · \(account.accountType == "BROKERAGE" ? "종합매매" : account.accountType)")
                                .tag(Int64?.some(account.accountSeq))
                        }
                    }
                    if loadingAccounts { ProgressView().controlSize(.small) }
                }
                Picker("표시 기준", selection: $mode) {
                    ForEach(AssetMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.radioGroup)
                Picker("수익 기준", selection: $afterCost) {
                    Text("원본 수익").tag(false)
                    Text("수수료·세금 제외").tag(true)
                }
                .pickerStyle(.segmented)
                .disabled(mode != .total)
                Text(mode == .total
                     ? "수수료·세금 제외는 토스증권이 계산한 세후 손익을 씁니다. 보유 종목 목록의 종목별 손익에도 같은 기준이 적용됩니다."
                     : "일간 손익은 원본 기준만 제공됩니다.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .formStyle(.columns)

            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("취소", action: dismiss).keyboardShortcut(.cancelAction)
                Button(existing == nil ? "추가" : "저장") {
                    let config = AssetItemConfig(label: label, accountSeq: accountSeq, mode: mode, afterCost: afterCost)
                    env.store.upsert(MenuItemConfig(id: existing?.id ?? UUID(), kind: .asset(config)))
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task {
            guard data.accounts.isEmpty else { return }
            loadingAccounts = true
            defer { loadingAccounts = false }
            do {
                _ = try await data.loadAccounts()
            } catch {
                self.error = "계좌 목록을 불러오지 못했습니다: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @ObservedObject var settings: AppSettings
    let env: AppEnvironment
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Picker("갱신 주기", selection: $settings.refreshInterval) {
                Text("5초").tag(5.0)
                Text("10초").tag(10.0)
                Text("15초").tag(15.0)
                Text("30초").tag(30.0)
                Text("1분").tag(60.0)
                Text("5분").tag(300.0)
            }
            .onChange(of: settings.refreshInterval) { _, _ in env.data.start() }

            Picker("팝오버 색상 규칙", selection: $settings.koreanColorConvention) {
                Text("상승 빨강 · 하락 파랑 (국내식)").tag(true)
                Text("상승 초록 · 하락 빨강 (해외식)").tag(false)
            }

            Toggle("로그인 시 자동 실행", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, newValue in
                    do {
                        try LaunchAtLogin.set(newValue)
                        launchError = nil
                    } catch {
                        launchError = "설정하지 못했습니다: \(error.localizedDescription) (.app 번들로 실행해야 동작합니다)"
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                }
            if let launchError {
                Text(launchError).font(.caption).foregroundStyle(.red)
            }

            Section {
                Text("데이터 출처: 토스증권 Open API (REST). 시세는 갱신 주기마다 일괄 조회하며, 그룹별 호출 한도를 넘지 않도록 자동 조절합니다.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("TossBar 종료") { env.quit() }
            }
        }
        .formStyle(.grouped)
        .padding(10)
    }
}
