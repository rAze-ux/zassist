import Foundation

/// Клиент Supabase: аутентификация + доступ к таблицам через REST API.
/// Сторонние библиотеки не используются — только URLSession.
final class SupabaseService {
    let baseURL: String
    let anonKey: String
    private let session = URLSession.shared

    init(baseURL: String, anonKey: String) {
        var url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if url.hasSuffix("/") { url.removeLast() }
        self.baseURL = url
        self.anonKey = anonKey
    }

    // MARK: - Базовый запрос

    private func request(_ method: String,
                         _ path: String,
                         token: String? = nil,
                         query: [String] = [],
                         extraHeaders: [String: String] = [:],
                         body: (any Encodable)? = nil) throws -> URLRequest {
        guard var components = URLComponents(string: baseURL + path) else {
            throw AppError.notConfigured
        }
        if !query.isEmpty {
            components.percentEncodedQuery = query.joined(separator: "&")
        }
        guard let url = components.url else { throw AppError.notConfigured }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(anonKey, forHTTPHeaderField: "apikey")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (key, value) in extraHeaders {
            req.setValue(value, forHTTPHeaderField: key)
        }
        if let token {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = try JSONEncoder().encode(AnyEncodable(body))
        }
        return req
    }

    private func send(_ req: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw AppError.network(error)
        }
        guard let http = response as? HTTPURLResponse else { throw AppError.invalidResponse }
        guard http.statusCode < 300 else { throw mapError(data: data, status: http.statusCode) }
        return data
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder.supabase.decode(T.self, from: data)
        } catch {
            throw AppError.invalidResponse
        }
    }

    private func mapError(data: Data, status: Int) -> AppError {
        if let body = try? JSONDecoder().decode(ServerError.self, from: data) {
            let raw = body.error ?? body.msg ?? body.message
            switch raw ?? "" {
            case "Invalid login credentials":
                return .server("Неверный email или пароль")
            case "User already registered",
                 "A user with this email address has already been registered":
                return .server("Пользователь с таким email уже зарегистрирован")
            case "Email not confirmed":
                return .server("Email не подтверждён — проверьте почту")
            default:
                break
            }
            if let raw, !raw.isEmpty {
                return .server(raw)
            }
        }
        return .server("Ошибка сервера Supabase (код \(status))")
    }

    // MARK: - Аутентификация

    private struct Credentials: Codable {
        let email: String
        let password: String
    }

    private struct RefreshBody: Codable {
        let refreshToken: String
        enum CodingKeys: String, CodingKey { case refreshToken = "refresh_token" }
    }

    func signUp(email: String, password: String) async throws -> AuthSession {
        let req = try request("POST", "/auth/v1/signup", body: Credentials(email: email, password: password))
        let auth = try await decode(AuthSession.self, from: await send(req))
        guard !auth.accessToken.isEmpty else {
            throw AppError.server("Аккаунт создан. Откройте письмо от Supabase, подтвердите email и войдите.")
        }
        return auth
    }

    func signIn(email: String, password: String) async throws -> AuthSession {
        let req = try request("POST", "/auth/v1/token",
                              body: Credentials(email: email, password: password),
                              query: ["grant_type=password"])
        return try await decode(AuthSession.self, from: await send(req))
    }

    func refresh(_ refreshToken: String) async throws -> AuthSession {
        let req = try request("POST", "/auth/v1/token",
                              body: RefreshBody(refreshToken: refreshToken),
                              query: ["grant_type=refresh_token"])
        return try await decode(AuthSession.self, from: await send(req))
    }

    func signOut(token: String, refreshToken: String?) async {
        struct Body: Codable { let refreshToken: String? }
        guard let req = try? request("POST", "/auth/v1/signout", token: token,
                                     body: Body(refreshToken: refreshToken)) else { return }
        _ = try? await send(req)
    }

    // MARK: - Проекты

    func fetchProjects(token: String) async throws -> [Project] {
        let req = try request("GET", "/rest/v1/projects", token: token,
                              query: ["select=*", "order=created_at.desc"])
        return try await decode([Project].self, from: await send(req))
    }

    func createProject(token: String, userId: UUID, title: String) async throws -> Project {
        struct Body: Codable {
            let userId: UUID
            let title: String
            enum CodingKeys: String, CodingKey { case userId = "user_id", title }
        }
        let req = try request("POST", "/rest/v1/projects", token: token,
                              extraHeaders: ["Prefer": "return=representation"],
                              body: Body(userId: userId, title: title))
        let rows = try await decode([Project].self, from: await send(req))
        guard let project = rows.first else { throw AppError.invalidResponse }
        return project
    }

    func renameProject(token: String, id: UUID, title: String) async throws {
        struct Body: Codable { let title: String }
        let req = try request("PATCH", "/rest/v1/projects", token: token,
                              body: Body(title: title), query: ["id=eq.\(id.uuidString)"])
        _ = try await send(req)
    }

    func deleteProject(token: String, id: UUID) async throws {
        let req = try request("DELETE", "/rest/v1/projects", token: token,
                              query: ["id=eq.\(id.uuidString)"])
        _ = try await send(req)
    }

    // MARK: - Сообщения

    func fetchMessages(token: String, projectId: UUID) async throws -> [ChatMessage] {
        let req = try request("GET", "/rest/v1/messages", token: token,
                              query: [
                                "select=*",
                                "project_id=eq.\(projectId.uuidString)",
                                "order=created_at.asc",
                              ])
        return try await decode([ChatMessage].self, from: await send(req))
    }

    func insertMessage(token: String, userId: UUID, projectId: UUID, role: String, content: String) async throws -> ChatMessage {
        struct Body: Codable {
            let projectId: UUID
            let userId: UUID
            let role: String
            let content: String
            enum CodingKeys: String, CodingKey {
                case projectId = "project_id"
                case userId = "user_id"
                case role, content
            }
        }
        let req = try request("POST", "/rest/v1/messages", token: token,
                              extraHeaders: ["Prefer": "return=representation"],
                              body: Body(projectId: projectId, userId: userId, role: role, content: content))
        let rows = try await decode([ChatMessage].self, from: await send(req))
        guard let message = rows.first else { throw AppError.invalidResponse }
        return message
    }

    func deleteMessages(token: String, projectId: UUID) async throws {
        let req = try request("DELETE", "/rest/v1/messages", token: token,
                              query: ["project_id=eq.\(projectId.uuidString)"])
        _ = try await send(req)
    }
}

private struct ServerError: Decodable {
    let error: String?
    let msg: String?
    let message: String?
}
