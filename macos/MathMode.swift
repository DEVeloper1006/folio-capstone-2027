import Foundation

struct MathBinding: Codable, Equatable, Sendable {
    let key: String
    let label: String
    let before: String
    let after: String
}

struct MathMode: Codable, Equatable, Sendable {
    static let builtinIDs = ["linalg", "calculus", "proof"]
    let id: String
    let title: String
    let summary: String
    let bindings: [MathBinding]

    func validate() throws {
        guard id.range(of: "^[a-z][a-z0-9-]{0,79}$", options: .regularExpression) != nil,
              !(Self.builtinIDs + ["new", "uncertain"]).contains(id), Self.text(title, limit: 48), Self.text(summary, limit: 300),
              !["new", "linalg", "calc", "proof"].contains(title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()),
              (3...8).contains(bindings.count), Set(bindings.map(\.key)).count == bindings.count else {
            throw AssistantError.invalidMode
        }
        for binding in bindings {
            guard binding.key.range(of: "^[a-z]$", options: .regularExpression) != nil,
                  Self.text(binding.label, limit: 80), Self.text(binding.before + binding.after, limit: 1200) else { throw AssistantError.invalidMode }
            let source = binding.before + binding.after
            guard source.range(of: #"(?<!\\)\$"#, options: .regularExpression) == nil,
                  !source.contains("{{cursor}}"),
                  source.range(of: #"\\(?:require|href|url|htmlClass|htmlId|htmlStyle|class|cssId|style|def|gdef|newcommand|renewcommand|let|includegraphics|input|include|write|openout|read)\b"#, options: .regularExpression) == nil else {
                throw AssistantError.invalidMode
            }
        }
    }

    static func text(_ value: String, limit: Int) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.count <= limit &&
        value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) || $0 == "\n" || $0 == "\t" }
    }
}

struct ModeSummary: Codable, Sendable {
    let id: String
    let title: String
    let summary: String
}

struct ModeDecision: Codable, Sendable {
    enum Action { case select, create, uncertain }
    let modeID: String
    let topic: String
    let reason: String
    var action: Action { modeID == "new" ? .create : modeID == "uncertain" ? .uncertain : .select }

    func validate(available: [ModeSummary]) throws {
        guard MathMode.text(reason, limit: 500), topic.count <= 100,
              (action == .select ? available.contains { $0.id == modeID } : ["new", "uncertain"].contains(modeID)),
              (action == .create ? !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : true) else {
            throw AssistantError.invalidMode
        }
    }
}

struct ModeDraft: Codable, Sendable {
    struct Binding: Codable, Sendable {
        let key: String
        let label: String
        let latex: String

        func materialize() throws -> MathBinding {
            let parts = latex.components(separatedBy: "#1")
            guard parts.count == 2 else { throw AssistantError.invalidMode }
            // Group the argument so textual substitution cannot merge it into a TeX command.
            return MathBinding(key: key, label: label, before: parts[0] + "{", after: "}" + parts[1])
        }
    }
    let title: String
    let summary: String
    let bindings: [Binding]

    func materialize() throws -> MathMode {
        let stem = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard !stem.isEmpty else { throw AssistantError.invalidMode }
        let mode = MathMode(id: "mode-" + stem, title: title, summary: summary, bindings: try bindings.map { try $0.materialize() })
        try mode.validate()
        return mode
    }
}
