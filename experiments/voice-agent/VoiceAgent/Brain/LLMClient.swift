import Foundation

/// OpenAI-compatible chat message as accepted by OpenRouter.
struct ChatMessage: Codable, Sendable, Identifiable, Equatable {
    enum Role: String, Codable, Sendable { case system, user, assistant }

    var id = UUID()
    let role: Role
    let content: String

    private enum CodingKeys: String, CodingKey { case role, content }
}

enum LLMError: Error, CustomStringConvertible {
    case missingAPIKey
    case http(status: Int, body: String)
    case timeout
    case emptyResponse

    var description: String {
        switch self {
        case .missingAPIKey: "OpenRouter API key is not configured"
        case .http(let status, let body): "Chat HTTP \(status): \(body.prefix(200))"
        case .timeout: "Chat model timed out"
        case .emptyResponse: "Model returned no content"
        }
    }
}

/// Claude via OpenRouter `/chat/completions` (OpenAI-compatible). The chat fallback: the only
/// component that generates text, and its output only ever goes to the transcript and TTS.
actor LLMClient {
    private struct Request: Encodable {
        let model: String
        let messages: [ChatMessage]
        let maxTokens: Int
        let temperature: Double

        private enum CodingKeys: String, CodingKey {
            case model, messages, temperature
            case maxTokens = "max_tokens"
        }
    }

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func complete(
        _ messages: [ChatMessage],
        model: String? = nil,
        maxTokens: Int = 600,
        temperature: Double = 0.4
    ) async throws -> String {
        guard let key = Config.openRouterKey()?.value else { throw LLMError.missingAPIKey }

        var request = URLRequest(url: Config.chatCompletionsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("folio-voice-agent", forHTTPHeaderField: "X-Title")
        request.httpBody = try JSONEncoder().encode(
            Request(model: model ?? Config.chatModel, messages: messages, maxTokens: maxTokens, temperature: temperature)
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw LLMError.timeout
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw LLMError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let content = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else { throw LLMError.emptyResponse }
        return content
    }
}
