import Foundation

// MARK: - Ошибки приложения

enum AppError: LocalizedError {
    case notConfigured
    case signedOut
    case noAIKey
    case server(String)
    case network(Error)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Приложение не настроено — укажите адрес и ключ Supabase"
        case .signedOut:
            return "Сессия истекла — войдите заново"
        case .noAIKey:
            return "Не задан API-ключ Z.AI — добавьте его в Настройках"
        case .server(let message):
            return message
        case .network(let error):
            return "Нет соединения: \(error.localizedDescription)"
        case .invalidResponse:
            return "Не удалось прочитать ответ сервера"
        }
    }
}

// MARK: - Модели данных

struct Project: Identifiable, Codable, Equatable {
    let id: UUID
    let userId: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title
        case userId = "user_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let projectId: UUID
    let role: String // "user" | "assistant"
    var content: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, role, content
        case projectId = "project_id"
        case createdAt = "created_at"
    }
}

// MARK: - Auth

struct AuthUser: Codable {
    let id: UUID
    let email: String?
}

struct AuthSession: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval?
    let user: AuthUser?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

/// Локально сохранённая сессия (Keychain).
struct StoredSession: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var userId: UUID
    var email: String?

    init(auth: AuthSession, fallback: StoredSession? = nil) {
        accessToken = auth.accessToken
        refreshToken = auth.refreshToken ?? fallback?.refreshToken
        expiresAt = Date().addingTimeInterval(max(120, (auth.expiresIn ?? 3600) - 120))
        userId = auth.user?.id ?? fallback?.userId ?? UUID()
        email = auth.user?.email ?? fallback?.email
    }
}

// MARK: - Вспомогательное

/// Коробка, чтобы класть любые Codable-тело в один URLRequest.
struct AnyEncodable: Encodable {
    private let encodeTo: (Encoder) throws -> Void

    init(_ wrapped: any Encodable) {
        encodeTo = { encoder in try wrapped.encode(to: encoder) }
    }

    func encode(to encoder: Encoder) throws {
        try encodeTo(encoder)
    }
}

extension JSONDecoder {
    /// Supabase отдаёт даты в ISO 8601 (иногда с долями секунды).
    static let supabase: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let raw = try container.decode(String.self)
            if let date = SupabaseDates.fractional.date(from: raw) ?? SupabaseDates.plain.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Неизвестный формат даты: \(raw)")
        }
        return decoder
    }()
}

private enum SupabaseDates {
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
