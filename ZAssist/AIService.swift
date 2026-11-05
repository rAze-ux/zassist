import Foundation

/// Сообщение для API чата (OpenAI-совместимый формат Z.AI).
struct AIMessage: Codable {
    let role: String
    let content: String
}

enum AIError: LocalizedError {
    case empty

    var errorDescription: String? {
        "Модель вернула пустой ответ — попробуйте ещё раз"
    }
}

/// Клиент чата Z.AI (модели GLM) с потоковой выдачей ответа.
final class AIService {
    let endpoint: URL
    let apiKey: String
    private let session: URLSession

    init?(baseURL: String, apiKey: String) {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if base.hasSuffix("/") { base.removeLast() }
        guard let endpoint = URL(string: base + "/chat/completions") else { return nil }
        self.endpoint = endpoint
        self.apiKey = apiKey
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 600
        config.timeoutIntervalForResource = 1800
        self.session = URLSession(configuration: config)
    }

    private struct RequestBody: Codable {
        let model: String
        let messages: [AIMessage]
        let stream: Bool
    }

    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable { let content: String? }
            let delta: Delta?
        }
        let choices: [Choice]
    }

    /// Возвращает текст ответа кусками по мере генерации (SSE-стрим).
    func stream(messages: [AIMessage], model: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var req = URLRequest(url: endpoint)
                    req.httpMethod = "POST"
                    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.httpBody = try JSONEncoder().encode(RequestBody(model: model, messages: messages, stream: true))

                    let (bytes, response) = try await session.bytes(for: req)
                    if let http = response as? HTTPURLResponse, http.statusCode >= 300 {
                        var body = ""
                        for try await line in bytes.lines { body += line + "\n" }
                        continuation.finish(throwing: AppError.server("Ошибка API Z.AI (код \(http.statusCode)). \(body.prefix(300))"))
                        return
                    }

                    var received = false
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                              let text = chunk.choices.first?.delta?.content,
                              !text.isEmpty
                        else { continue }
                        received = true
                        continuation.yield(text)
                    }
                    continuation.finish(throwing: received ? nil : AIError.empty)
                } catch {
                    if error is AppError || error is AIError {
                        continuation.finish(throwing: error)
                    } else if let urlError = error as? URLError {
                        continuation.finish(throwing: AppError.network(urlError))
                    } else {
                        continuation.finish(throwing: AppError.server(error.localizedDescription))
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
