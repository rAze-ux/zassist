import SwiftUI

/// Первый запуск: подключение к вашему проекту Supabase.
struct SetupView: View {
    @EnvironmentObject private var state: AppState
    @State private var url = ""
    @State private var key = ""
    @State private var validationError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("1. Создайте бесплатный проект на supabase.com\n2. В SQL Editor выполните скрипт из файла supabase/schema.sql\n3. Project Settings → API: скопируйте «Project URL» и «anon public key»")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Как получить данные")
                }

                Section("Подключение к Supabase") {
                    TextField("Project URL (https://…​.supabase.co)", text: $url)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Anon public key", text: $key)
                        .keyboardType(.asciiCapable)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if let validationError {
                        Text(validationError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button("Сохранить и продолжить") { save() }
                        .frame(maxWidth: .infinity)
                } footer: {
                    Text("Подробная пошаговая инструкция — в файле README проекта.")
                }
            }
            .navigationTitle("Настройка")
        }
    }

    private func save() {
        let cleanURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanURL.hasPrefix("https://"), cleanURL.contains(".") else {
            validationError = "URL должен начинаться с https:// (например, https://abcdefgh.supabase.co)"
            return
        }
        guard cleanKey.count > 20 else {
            validationError = "Похоже, ключ введён не полностью — это длинная строка"
            return
        }
        state.supabaseURL = cleanURL
        state.supabaseAnonKey = cleanKey
        validationError = nil
    }
}
