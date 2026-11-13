import SwiftUI

struct SettingsView: View {
    let env: AppEnvironment
    @AppStorage("settingsTab") private var tab = "api"

    var body: some View {
        TabView(selection: $tab) {
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
            GeneralSettingsView(env: env)
                .tabItem { Label("일반", systemImage: "gearshape") }
                .tag("general")
        }
        .frame(width: 580, height: 480)
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    let env: AppEnvironment
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchError: String?

    var body: some View {
        Form {
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
                Text("데이터 출처: 토스증권 Open API (REST).")
                    .font(.caption).foregroundStyle(.secondary)
                Button("TossBar 종료") { env.quit() }
            }
        }
        .formStyle(.grouped)
        .padding(10)
    }
}
