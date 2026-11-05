import SwiftUI

/// Вход или регистрация по email и паролю (Supabase Auth).
struct LoginView: View {
    @EnvironmentObject private var state: AppState
    @State private var email = ""
    @State private var password = ""
    @State private var isSignup = false
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("ZAssist")
                .font(.largeTitle.bold())
                .padding(.top, 10)
            Text("ИИ-ассистент с синхронизацией проектов")
                .foregroundStyle(.secondary)

            Spacer().frame(height: 28)

            Picker("Режим", selection: $isSignup) {
                Text("Вход").tag(false)
                Text("Регистрация").tag(true)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 32)

            VStack(spacing: 12) {
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                SecureField("Пароль", text: $password)
                    .textFieldStyle(.roundedBorder)
                if let errorText {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 16)

            Button {
                Task { await submit() }
            } label: {
                HStack(spacing: 8) {
                    if busy { ProgressView().tint(.white) }
                    Text(isSignup ? "Создать аккаунт" : "Войти")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(busy || email.isEmpty || password.isEmpty)
            .padding(.horizontal, 32)
            .padding(.top, 16)

            Spacer()

            Text("Аккаунт и история чатов хранятся в вашем Supabase")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 16)
        }
    }

    @MainActor
    private func submit() async {
        busy = true
        defer { busy = false }
        errorText = nil
        do {
            if password.count < 6 {
                throw AppError.server("Пароль — минимум 6 символов")
            }
            if isSignup {
                try await state.signUp(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            } else {
                try await state.signIn(email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password)
            }
        } catch {
            errorText = AppState.describe(error)
        }
    }
}
