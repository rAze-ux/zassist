import SwiftUI

/// Настройки: API-ключ Z.AI, модель, параметры Supabase, выход из аккаунта.
struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            Section {
                SecureField("API-ключ Z.AI", text: $state.zaiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Picker("Модель", selection: $state.model) {
                    Text("GLM-4.7-Flash — бесплатно (рекомендую)").tag("glm-4.7-flash")
                    Text("GLM-4.5-Flash — бесплатно").tag("glm-4.5-flash")
                    Text("GLM-5.3-Flash — платная, дешёвая").tag("glm-5.3-flash")
                    Text("GLM-5.3 — платная, самая умная").tag("glm-5.3")
                }
                TextField("Адрес API", text: $state.zaiBaseURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("ИИ (Z.AI)")
            } footer: {
                Text("Ключ создаётся в консоли z.ai → API Keys. Ключ хранится только на этом iPhone (в Keychain). Модель и адрес можно менять в любой момент.")
            }

            Section {
                TextField("Project URL", text: $state.supabaseURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Anon key", text: $state.supabaseAnonKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Supabase")
            } footer: {
                Text("Хранилище аккаунтов и синхронизации проектов.")
            }

            Section {
                LabeledContent("Email", value: state.session?.email ?? "—")
                Button("Выйти из аккаунта", role: .destructive) {
                    Task { await state.logout() }
                }
            } header: {
                Text("Аккаунт")
            }

            Section {
                LabeledContent("Версия", value: "1.0")
            } header: {
                Text("О приложении")
            } footer: {
                Text("ZAssist — сборка через GitHub Actions, хранение и синхронизация через Supabase, ответы генерирует GLM по вашему ключу Z.AI.")
            }
        }
        .navigationTitle("Настройки")
    }
}
