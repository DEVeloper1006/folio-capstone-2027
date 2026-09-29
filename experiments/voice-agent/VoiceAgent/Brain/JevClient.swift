import Foundation

// MARK: - System One wire types
//
// POST https://openrouter.ai/api/v1/systemone
// {
//   "model": "jev-latest",
//   "state": "<context string>",
//   "questions": {
//     "<name>": { "type": "choice", "instructions": "...", "criteria": { "<key>": "<description>" } },
//     "<name>": { "type": "noul",   "instructions": "..." }
//   }
// }
// → { "id": "...", "model": "...", "answers": { "<name>": { "type": "choice", "choice": "<key>" } }, "usage": {...} }

/// A typed question. Jev answers every question in a request in a single parallel pass.
enum JevQuestion: Encodable, Sendable {
    case choice(instructions: String, criteria: [String: String])
    case noul(instructions: String)

    private enum CodingKeys: String, CodingKey { case type, instructions, criteria }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .choice(let instructions, let criteria):
            try container.encode("choice", forKey: .type)
            try container.encode(instructions, forKey: .instructions)
            try container.encode(criteria, forKey: .criteria)
        case .noul(let instructions):
            try container.encode("noul", forKey: .type)
            try container.encode(instructions, forKey: .instructions)
        }
    }
}

/// A typed answer. Unknown answer types (e.g. future `score`) decode to `.unknown` instead of failing.
enum JevAnswer: Decodable, Sendable, Equatable {
    case choice(String)
    case noul(Double)
    case score(Double)
    case unknown(type: String)

    private enum CodingKeys: String, CodingKey { case type, choice, noul, score }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "choice": self = .choice(try container.decode(String.self, forKey: .choice))
        case "noul": self = .noul(try container.decode(Double.self, forKey: .noul))
        case "score": self = .score(try container.decode(Double.self, forKey: .score))
        default: self = .unknown(type: type)
        }
    }

    var choiceValue: String? {
        if case .choice(let value) = self { return value }
        return nil
    }

    /// Probability-like value for `noul` / `score` answers.
    var probability: Double? {
        switch self {
        case .noul(let value), .score(let value): value
        default: nil
        }
    }
}

struct SystemOneRequest: Encodable, Sendable {
    let model: String
    let state: String
    let questions: [String: JevQuestion]
}

struct SystemOneResponse: Decodable, Sendable {
    struct Usage: Decodable, Sendable {
        let inputTokens: Int?
        let outputTokens: Int?
        let cost: Double?

        private enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case cost
        }
    }

    let id: String?
    let model: String?
    let answers: [String: JevAnswer]
    let usage: Usage?
}

/// A decoded decision plus client-side latency.
struct JevDecision: Sendable {
    let answers: [String: JevAnswer]
    let latency: Duration
    let model: String?

    subscript(_ name: String) -> JevAnswer? { answers[name] }

    func choice(_ name: String) -> String? { answers[name]?.choiceValue }
}

// MARK: - Client

enum JevError: Error, CustomStringConvertible {
    case missingAPIKey
    case http(status: Int, body: String)
    case invalidChoice(question: String, value: String?)

    var description: String {
        switch self {
        case .missingAPIKey: "OpenRouter API key is not configured"
        case .http(let status, let body): "System One HTTP \(status): \(body.prefix(200))"
        case .invalidChoice(let question, let value): "Jev returned invalid choice for \(question): \(value ?? "nil")"
        }
    }
}

/// OpenRouter System One client for TypeSafe Jev.
actor JevClient {
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private(set) var lastLatency: Duration?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func decide(state: String, questions: [String: JevQuestion], model: String? = nil) async throws -> JevDecision {
        guard let key = Config.openRouterKey()?.value else { throw JevError.missingAPIKey }

        var request = URLRequest(url: Config.systemOneURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("folio-voice-agent", forHTTPHeaderField: "X-Title")
        request.httpBody = try encoder.encode(
            SystemOneRequest(model: model ?? Config.jevModel, state: state, questions: questions)
        )

        let clock = ContinuousClock()
        let start = clock.now
        let (data, response) = try await session.data(for: request)
        let latency = clock.now - start
        lastLatency = latency

        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw JevError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }

        let decoded = try decoder.decode(SystemOneResponse.self, from: data)
        return JevDecision(answers: decoded.answers, latency: latency, model: decoded.model)
    }
}
