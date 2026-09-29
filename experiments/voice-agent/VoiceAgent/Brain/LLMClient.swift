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
    case emptyResponse

    var description: String {
        switch self {
        case .missingAPIKey: "OpenRouter API key is not configured"
        case .http(let status, let body): "Chat HTTP \(status): \(body.prefix(200))"
        case .emptyResponse: "Model returned no content"
        }
    }
}

/// Claude via OpenRouter `/chat/completions`. Used for chat replies and for the one place
/// the pipeline needs free text: extracting the literal string for TYPE_TEXT.
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

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw LLMError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let content = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !content.isEmpty else { throw LLMError.emptyResponse }
        return content
    }

    /// Returns exactly the text the user wants typed, or nil if the utterance contains none.
    /// Only this string ever reaches TYPE_TEXT; the model cannot choose targets or actions here.
    func extractTextToType(from utterance: String, goal: String? = nil) async throws -> String? {
        if let quoted = Self.regexExtract(utterance) { return quoted }

        let system = """
        You extract the literal text a user wants typed on their computer.
        Reply with ONLY that text — no quotes, no explanation.
        If the request contains no text to type, reply with exactly: <none>
        """
        var prompt = "Request: \(utterance)"
        if let goal, goal != utterance { prompt += "\nOverall goal: \(goal)" }

        let reply = try await complete(
            [ChatMessage(role: .system, content: system), ChatMessage(role: .user, content: prompt)],
            model: Config.extractModel,
            maxTokens: 300,
            temperature: 0
        )
        return reply == "<none>" ? nil : reply
    }

    /// Fast path: `type "hello world"` / `type 'hello'` / `write “hi”`.
    static func regexExtract(_ utterance: String) -> String? {
        let pattern = #"(?i)\b(?:type|write|enter)\b\s*[\"“'‘](.+?)[\"”'’]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: utterance, range: NSRange(utterance.startIndex..., in: utterance)),
              let range = Range(match.range(at: 1), in: utterance) else { return nil }
        return String(utterance[range])
    }
}
