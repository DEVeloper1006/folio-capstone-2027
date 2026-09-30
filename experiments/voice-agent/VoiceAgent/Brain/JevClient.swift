import Foundation

// MARK: - Decisions API wire types
//
// Jev is a decision model, not a chat model: it never generates text. It picks among options
// that code supplies and returns probabilities.
//
// POST https://openrouter.ai/api/alpha/decisions
// {
//   "model": "typesafe/jev-1.13",
//   "state": "<transcript + AX element table>",
//   "questions": {
//     "intent":       { "type": "choice", "instructions": "...", "criteria": { "OPEN_APP": "...", ... } },
//     "target_index": { "type": "choice", "instructions": "...", "criteria": { "0": "button 'Send'", ... } },
//     "goal_met":     { "type": "noul",   "instructions": "...", "criteria": { "true": "...", "false": "..." } }
//   }
// }
// → {
//   "id": "gen-dec-…", "provider": "TypeSafe", "model": "typesafe/jev-1.13-20260917",
//   "answers": {
//     "intent":   { "type": "choice", "choice": "OPEN_APP", "confidence": 0.98, "probabilities": { "OPEN_APP": 0.98, ... } },
//     "goal_met": { "type": "noul", "noul": 0.03 }
//   },
//   "usage": { "input_tokens": 455, "output_tokens": 86, "cost": 1.9e-05 }
// }
//
// Shape verified with a live call on 2026-09-30.

/// A typed question. Jev answers every question in a request in a single parallel pass.
enum JevQuestion: Encodable, Sendable {
    case choice(instructions: String, criteria: [String: String])
    /// Yes/no probability. OpenRouter requires both `true` and `false` criteria when criteria are sent.
    case noul(instructions: String, whenTrue: String? = nil, whenFalse: String? = nil)

    private enum CodingKeys: String, CodingKey { case type, instructions, criteria }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .choice(let instructions, let criteria):
            try container.encode("choice", forKey: .type)
            try container.encode(instructions, forKey: .instructions)
            try container.encode(criteria, forKey: .criteria)
        case .noul(let instructions, let whenTrue, let whenFalse):
            try container.encode("noul", forKey: .type)
            try container.encode(instructions, forKey: .instructions)
            if let whenTrue, let whenFalse {
                try container.encode(["true": whenTrue, "false": whenFalse], forKey: .criteria)
            }
        }
    }
}

/// A typed answer. Unknown answer types decode to `.unknown` instead of failing the whole decision.
enum JevAnswer: Decodable, Sendable, Equatable {
    case choice(String, confidence: Double?, probabilities: [String: Double]?)
    case noul(Double)
    case score(Double, confidence: Double?)
    case unknown(type: String)

    private enum CodingKeys: String, CodingKey { case type, choice, noul, score, confidence, probabilities }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "choice":
            self = .choice(
                try container.decode(String.self, forKey: .choice),
                confidence: try container.decodeIfPresent(Double.self, forKey: .confidence),
                probabilities: try container.decodeIfPresent([String: Double].self, forKey: .probabilities)
            )
        case "noul":
            self = .noul(try container.decode(Double.self, forKey: .noul))
        case "score":
            self = .score(
                try container.decode(Double.self, forKey: .score),
                confidence: try container.decodeIfPresent(Double.self, forKey: .confidence)
            )
        default:
            self = .unknown(type: type)
        }
    }

    var choiceValue: String? {
        if case .choice(let value, _, _) = self { return value }
        return nil
    }

    var confidence: Double? {
        switch self {
        case .choice(_, let confidence, _), .score(_, let confidence): confidence
        default: nil
        }
    }

    /// Probability of "yes" for `noul` answers.
    var probability: Double? {
        if case .noul(let value) = self { return value }
        return nil
    }
}

struct DecisionsRequest: Encodable, Sendable {
    let model: String
    let state: String
    let questions: [String: JevQuestion]
}

struct DecisionsResponse: Decodable, Sendable {
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

    func confidence(_ name: String) -> Double? { answers[name]?.confidence }
}

// MARK: - Client

enum JevError: Error, CustomStringConvertible {
    case missingAPIKey
    case http(status: Int, body: String)
    case timeout
    case decoding(body: String)
    case invalidChoice(question: String, value: String?)

    var description: String {
        switch self {
        case .missingAPIKey: "OpenRouter API key is not configured"
        case .http(let status, let body): "Jev HTTP \(status): \(body.prefix(200))"
        case .timeout: "Jev timed out"
        case .decoding(let body): "Unexpected Jev response: \(body.prefix(200))"
        case .invalidChoice(let question, let value): "Jev returned invalid choice for \(question): \(value ?? "nil")"
        }
    }

    /// Transient failures worth one retry.
    var isRetryable: Bool {
        switch self {
        case .timeout: true
        case .http(let status, _): status == 429 || (500..<600).contains(status)
        default: false
        }
    }
}

/// OpenRouter Decisions API client for TypeSafe Jev.
actor JevClient {
    private let session: URLSession
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// End-to-end latency is ~0.6 s in practice, so 3 s is generous but keeps a voice turn responsive.
    var timeout: TimeInterval = 3
    var retryDelay: Duration = .milliseconds(150)

    private(set) var lastLatency: Duration?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func decide(state: String, questions: [String: JevQuestion], model: String? = nil) async throws -> JevDecision {
        guard let key = Config.openRouterKey()?.value else { throw JevError.missingAPIKey }
        let body = try encoder.encode(
            DecisionsRequest(model: model ?? Config.jevModel, state: state, questions: questions)
        )

        do {
            return try await send(body, key: key)
        } catch let error as JevError where error.isRetryable {
            try await Task.sleep(for: retryDelay)
            return try await send(body, key: key)
        }
    }

    private func send(_ body: Data, key: String) async throws -> JevDecision {
        var request = URLRequest(url: Config.decisionsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("folio-voice-agent", forHTTPHeaderField: "X-Title")
        request.httpBody = body

        let clock = ContinuousClock()
        let start = clock.now
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw JevError.timeout
        }
        let latency = clock.now - start
        lastLatency = latency

        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw JevError.http(status: status, body: String(decoding: data, as: UTF8.self))
        }

        guard let decoded = try? decoder.decode(DecisionsResponse.self, from: data) else {
            throw JevError.decoding(body: String(decoding: data, as: UTF8.self))
        }
        return JevDecision(answers: decoded.answers, latency: latency, model: decoded.model)
    }
}
