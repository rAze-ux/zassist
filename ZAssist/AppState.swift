import Foundation
import SwiftUI

/// Состояние всего приложения: конфигурация, сессия, список проектов.
@MainActor
final class AppState: ObservableObject {

    // MARK: - Состояние

    @Published var ready = false
    @Published private(set) var session: StoredSession?
    @Published var projects: [Project] = []
    @Published var loadingProjects = false
    @Published var lastError: String?

    // MARK: - Конфигурация (сохраняется сразу при изменении)

    @Published var supabaseURL: String {
        didSet { UserDefaults.standard.set(supabaseURL, forKey: "cfg.supabaseURL") }
    }
    @Published var supabaseAnonKey: String {
        didSet { UserDefaults.standard.set(supabaseAnonKey, forKey: "cfg.supabaseAnonKey") }
    }
    @Published var zaiBaseURL: String {
        didSet { UserDefaults.standard.set(zaiBaseURL, forKey: "cfg.zaiBaseURL") }
    }
    @Published var model: String {
        didSet { UserDefaults.standard.set(model, forKey: "cfg.model.v2") }
    }
    @Published var zaiKey: String {
        didSet { Keychain.set(zaiKey.isEmpty ? nil : zaiKey, for: "zai_key") }
    }

    var isConfigured: Bool {
        supabaseURL.hasPrefix("https://") && supabaseAnonKey.count > 20
    }

    var supabase: SupabaseService {
        SupabaseService(baseURL: supabaseURL, anonKey: supabaseAnonKey)
    }

    func makeAI() -> AIService? {
        let key = zaiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return AIService(baseURL: zaiBaseURL, apiKey: key)
    }

    // MARK: - Инициализация

    init() {
        let defaults = UserDefaults.standard
        supabaseURL = defaults.string(forKey: "cfg.supabaseURL") ?? AppConfig.defaultSupabaseURL
        supabaseAnonKey = defaults.string(forKey: "cfg.supabaseAnonKey") ?? AppConfig.defaultSupabaseAnonKey
        zaiBaseURL = defaults.string(forKey: "cfg.zaiBaseURL") ?? AppConfig.defaultZaiBaseURL
        model = defaults.string(forKey: "cfg.model.v2") ?? AppConfig.defaultModel
        zaiKey = Keychain.get("zai_key") ?? ""

        if let raw = Keychain.get("session"),
           let data = raw.data(using: .utf8),
           let stored = try? JSONDecoder().decode(StoredSession.self, from: data) {
            session = stored
            ready = false // ждём restore()
        } else {
            session = nil
            ready = true
        }
    }

    // MARK: - Сессия

    /// Восстановление сессии при запуске (обновляет токен, если истёк).
    func restore() async {
        guard let stored = session else {
            ready = true
            return
        }
        if stored.expiresAt < Date().addingTimeInterval(60), let refreshToken = stored.refreshToken {
            if let fresh = try? await supabase.refresh(refreshToken) {
                session = StoredSession(auth: fresh, fallback: stored)
                persistSession()
            } else {
                session = nil
                Keychain.delete("session")
            }
        }
        ready = true
        await loadProjects()
    }

    /// Валидная сессия с автоматическим обновлением токена.
    func ensureValidSession() async throws -> StoredSession {
        guard var current = session else { throw AppError.signedOut }
        if current.expiresAt < Date().addingTimeInterval(60) {
            guard let refreshToken = current.refreshToken,
                  let fresh = try? await supabase.refresh(refreshToken)
            else {
                session = nil
                Keychain.delete("session")
                throw AppError.signedOut
            }
            current = StoredSession(auth: fresh, fallback: current)
            session = current
            persistSession()
        }
        return current
    }

    private func store(_ auth: AuthSession) throws {
        guard auth.user != nil else {
            throw AppError.server("Не удалось получить данные пользователя")
        }
        session = StoredSession(auth: auth)
        persistSession()
    }

    private func persistSession() {
        guard let current = session,
              let data = try? JSONEncoder().encode(current),
              let raw = String(data: data, encoding: .utf8)
        else { return }
        Keychain.set(raw, for: "session")
    }

    // MARK: - Вход / регистрация / выход

    func signIn(email: String, password: String) async throws {
        let auth = try await supabase.signIn(email: email, password: password)
        try store(auth)
        await loadProjects()
    }

    func signUp(email: String, password: String) async throws {
        let auth = try await supabase.signUp(email: email, password: password)
        try store(auth)
        await loadProjects()
    }

    func logout() async {
        if let current = session {
            await supabase.signOut(token: current.accessToken, refreshToken: current.refreshToken)
        }
        session = nil
        projects = []
        Keychain.delete("session")
    }

    // MARK: - Проекты

    static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    func loadProjects() async {
        guard session != nil else { return }
        loadingProjects = true
        defer { loadingProjects = false }
        do {
            let current = try await ensureValidSession()
            projects = try await supabase.fetchProjects(token: current.accessToken)
        } catch {
            lastError = Self.describe(error)
        }
    }

    func createProject(title: String) async {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        do {
            let current = try await ensureValidSession()
            let project = try await supabase.createProject(token: current.accessToken, userId: current.userId, title: clean)
            projects.insert(project, at: 0)
        } catch {
            lastError = Self.describe(error)
        }
    }

    func renameProject(_ project: Project, title: String) async {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        do {
            let current = try await ensureValidSession()
            try await supabase.renameProject(token: current.accessToken, id: project.id, title: clean)
            if let index = projects.firstIndex(where: { $0.id == project.id }) {
                projects[index].title = clean
            }
        } catch {
            lastError = Self.describe(error)
        }
    }

    func deleteProject(_ project: Project) async {
        do {
            let current = try await ensureValidSession()
            try await supabase.deleteProject(token: current.accessToken, id: project.id)
            projects.removeAll { $0.id == project.id }
        } catch {
            lastError = Self.describe(error)
        }
    }
}
