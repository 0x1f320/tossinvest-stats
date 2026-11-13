import AppKit
import SwiftUI

/// Client ID / Secret fields with a connection test. Used by onboarding and settings.
struct CredentialsForm: View {
    @ObservedObject var credentials: CredentialStore
    var onConnected: ([Account]) -> Void = { _ in }

    @State private var clientId = ""
    @State private var clientSecret = ""
    @State private var isTesting = false
    @State private var status: Status = .idle

    enum Status: Equatable {
        case idle
        case success(String)
        case failure(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    Text("Client ID").gridColumnAlignment(.trailing)
                    TextField("발급받은 client_id", text: $clientId)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Client Secret")
                    SecureField(credentials.hasSecret ? "저장됨 (변경 시에만 입력)" : "발급받은 client_secret", text: $clientSecret)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(save)
                }
            }

            HStack(spacing: 10) {
                Button(action: save) {
                    if isTesting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("저장 및 연결 테스트")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isTesting || clientId.nilIfBlank == nil || (clientSecret.nilIfBlank == nil && !credentials.hasSecret))

                if credentials.isConfigured {
                    Button("키 삭제", role: .destructive) {
                        Task {
                            await credentials.clear()
                            clientId = ""
                            clientSecret = ""
                            status = .idle
                        }
                    }
                }
                Spacer()
            }

            switch status {
            case .idle:
                EmptyView()
            case .success(let message):
                Label(message, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green).font(.callout)
            case .failure(let message):
                Label(message, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { clientId = credentials.clientId }
    }

    private func save() {
        guard !isTesting, clientId.nilIfBlank != nil else { return }
        isTesting = true
        status = .idle
        Task {
            defer { isTesting = false }
            do {
                let accounts = try await credentials.saveAndTest(clientId: clientId, clientSecret: clientSecret.nilIfBlank)
                clientSecret = ""
                status = .success(accounts.isEmpty
                                  ? "연결되었습니다. (조회 가능한 종합매매 계좌가 없습니다)"
                                  : "연결되었습니다. 계좌 \(accounts.count)개를 찾았습니다.")
                onConnected(accounts)
            } catch {
                status = .failure(error.localizedDescription)
            }
        }
    }
}

/// How to get the API keys.
struct CredentialsHelp: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("API 키 발급 방법").font(.subheadline.weight(.semibold))
            Text("1. PC 웹(토스증권 WTS)에 로그인 → 설정 → Open API 에서 클라이언트를 등록합니다.")
            Text("2. 이 Mac 이 사용하는 공인 IP 를 허용 IP 로 등록해야 합니다. (미등록 시 403)")
            Text("3. 발급된 client_id / client_secret 을 아래에 입력하세요. 키는 이 Mac 사용자만 읽을 수 있는 파일(~/Library/Application Support/TossBar)에 저장됩니다.")
            Text("※ 토스증권은 클라이언트당 토큰을 1개만 유효하게 유지합니다. 같은 키를 다른 프로그램과 함께 쓰면 서로의 토큰이 무효화되니 TossBar 전용 키를 쓰는 것을 권장합니다.")
                .foregroundStyle(.secondary)
            Link("토스증권 Open API 문서 열기", destination: URL(string: "https://developers.tossinvest.com/docs")!)
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// First-launch window: enter the keys, confirm the connection, then add starter items.
struct OnboardingView: View {
    let env: AppEnvironment
    var onFinish: () -> Void

    @ObservedObject private var credentials: CredentialStore
    @State private var connectedAccounts: [Account]?
    @State private var addSamsung = true

    init(env: AppEnvironment, onFinish: @escaping () -> Void) {
        self.env = env
        self.onFinish = onFinish
        self.credentials = env.credentials
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "chart.line.uptrend.xyaxis.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("TossBar 시작하기").font(.title2.weight(.semibold))
                    Text("토스증권 Open API 키를 입력하면 메뉴바에서 주가와 자산을 볼 수 있어요.")
                        .foregroundStyle(.secondary)
                }
            }

            CredentialsHelp()

            GroupBox {
                CredentialsForm(credentials: credentials) { accounts in
                    connectedAccounts = accounts
                }
                .padding(6)
            }

            if connectedAccounts != nil, env.store.items.isEmpty {
                GroupBox("메뉴바에 추가할 항목") {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("주가 — 삼성전자 (005930) 예시", isOn: $addSamsung)
                        Text("나중에 설정 > 항목에서 언제든 추가/삭제할 수 있습니다.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
            }

            HStack {
                Button("나중에 하기") { onFinish() }
                Spacer()
                Button("시작하기") {
                    if env.store.items.isEmpty, addSamsung {
                        env.store.upsert(MenuItemConfig(kind: .stock(StockItemConfig(symbol: "005930"))))
                    }
                    env.data.refreshSoon()
                    onFinish()
                }
                .buttonStyle(.borderedProminent)
                .disabled(connectedAccounts == nil)
            }
        }
        .padding(24)
        .frame(width: 520)
    }
}
