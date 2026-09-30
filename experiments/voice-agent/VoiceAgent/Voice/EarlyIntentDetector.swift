import Foundation

/// A single-shot command recognized from a *partial* transcript, safe to run before the user
/// finishes speaking.
struct EarlyIntent: Sendable, Equatable {
    enum Command: Sendable, Equatable {
        case openApp(String)
        case system(ActionKind)
        case scroll(ScrollDirection)
        case pressKey(KeyChord)
    }

    let command: Command
    /// Words of the transcript the command consumed ("open vs code" → 3).
    let consumedWords: Int
    /// True when more speech follows the command ("open Safari and …"), which proves the command
    /// phrase is complete.
    let followedByMore: Bool

    var intent: ActionIntent {
        switch command {
        case .openApp(let name): .openApp(name: name)
        case .system(let kind): .system(kind)
        case .scroll(let direction): .scroll(direction)
        case .pressKey(let chord): .pressKey(keyCode: chord.keyCode, modifiers: chord.flags)
        }
    }
}

/// Keyword prefix matcher for partial transcripts. No Jev call: partials arrive every ~300 ms and
/// Jev takes ~250 ms+, so only unambiguous command prefixes are handled here.
///
/// Fires only when both hold:
/// 1. **Resolves:** the app/website name resolves (via `resolveApp`) or the key is in `KeyChord`, and
///    the phrase runs exactly to a connector ("and", "then", a comma) or the end. "open mail chimp"
///    doesn't fire Mail.
/// 2. **Stable:** more words follow the command, or the same command matched the previous partial.
///    "open safari" fires on the second identical partial; "open safari and" fires at once.
///
/// Never produces TASK, CHAT, TYPE_TEXT or CLICK: those need the whole utterance.
@MainActor
struct EarlyIntentDetector {
    /// Returns true if an app or website with this spoken name can be opened.
    var resolveApp: @MainActor (String) -> Bool

    static let connectors: Set<String> = ["and", "then", "also"]
    static let maxAppNameWords = 4

    /// Spoken key names → registry keys. Built from `KeyChord.spokenName` plus common aliases.
    static let keyNames: [String: KeyChord] = {
        var names: [String: KeyChord] = [:]
        for chord in KeyChord.allCases {
            let spoken = chord.spokenName.lowercased()
            names[spoken] = chord
            if spoken.hasPrefix("command ") {
                names["cmd " + spoken.dropFirst("command ".count)] = chord
            }
        }
        names["enter"] = .returnKey
        names["esc"] = .escape
        names["backspace"] = .delete
        names["space bar"] = .space
        names["spacebar"] = .space
        for arrow in ["up", "down", "left", "right"] {
            names["\(arrow) arrow"] = names[arrow]
        }
        return names
    }()

    /// Matches `text` and applies the stability rule against the previous partial's match.
    func detect(_ text: String, previous: EarlyIntent?) -> EarlyIntent? {
        guard let match = match(text) else { return nil }
        return match.followedByMore || match.command == previous?.command ? match : nil
    }

    /// Match only (no stability rule): the command at the start of `text`, if any.
    func match(_ text: String) -> EarlyIntent? {
        let tokens = Self.tokens(text)
        guard let first = tokens.first else { return nil }
        let words = tokens.map(\.word)

        // Span: words after the verb up to (not including) a connector or a punctuation boundary.
        func span(from start: Int) -> (words: [String], end: Int) {
            var end = start
            while end < tokens.count, !Self.connectors.contains(tokens[end].word) {
                end += 1
                if tokens[end - 1].boundaryAfter { break }
            }
            return (Array(words[start..<end]), end)
        }
        func intent(_ command: EarlyIntent.Command, consumed: Int) -> EarlyIntent {
            EarlyIntent(command: command, consumedWords: consumed, followedByMore: consumed < tokens.count)
        }

        switch first.word {
        case "open":
            let (name, end) = span(from: 1)
            guard !name.isEmpty, name.count <= Self.maxAppNameWords else { return nil }
            let spoken = name.joined(separator: " ")
            guard resolveApp(spoken) else { return nil }
            return intent(.openApp(spoken), consumed: end)

        case "press":
            let (name, end) = span(from: 1)
            guard let chord = Self.keyNames[name.joined(separator: " ")] else { return nil }
            return intent(.pressKey(chord), consumed: end)

        case "scroll":
            let (rest, end) = span(from: 1)
            switch rest {
            case ["up"]: return intent(.scroll(.up), consumed: end)
            case ["down"]: return intent(.scroll(.down), consumed: end)
            default: return nil
            }

        case "volume":
            let (rest, end) = span(from: 1)
            switch rest {
            case ["up"]: return intent(.system(.volumeUp), consumed: end)
            case ["down"]: return intent(.system(.volumeDown), consumed: end)
            default: return nil
            }

        case "mute", "unmute":
            let (rest, end) = span(from: 0)
            guard rest.count == 1 else { return nil }
            return intent(.system(first.word == "mute" ? .mute : .unmute), consumed: end)

        case "turn", "toggle":
            let verbWords = first.word == "turn" ? 2 : 1
            guard first.word == "toggle" || (words.count > 1 && ["on", "off"].contains(words[1])) else { return nil }
            let (rest, end) = span(from: verbWords)
            guard ["do not disturb", "dnd", "focus"].contains(rest.joined(separator: " ")) else { return nil }
            return intent(.system(.toggleDoNotDisturb), consumed: end)

        default:
            return nil
        }
    }

    /// What's left of `text` after a command that already ran, or nil if `text` no longer starts
    /// with that command (the recognizer revised the words). Leading connectors are dropped, and
    /// the remainder keeps its original casing ("…and type Hello" stays "type Hello").
    func remainder(of text: String, after fired: EarlyIntent) -> String? {
        guard let match = match(text), match.command == fired.command else { return nil }
        var rest = Self.tokens(text).dropFirst(match.consumedWords)
        while let first = rest.first, Self.connectors.contains(first.word) {
            rest = rest.dropFirst()
        }
        return rest.map(\.original).joined(separator: " ")
    }

    // MARK: - Tokens

    struct Token {
        let original: String
        let word: String          // lowercased, punctuation stripped
        let boundaryAfter: Bool   // original ended with , . ; : ! ?
    }

    static func tokens(_ text: String) -> [Token] {
        let punctuation = CharacterSet(charactersIn: ",.;:!?\"“”")
        return text.replacingOccurrences(of: "-", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .compactMap { raw in
                let original = String(raw)
                let word = original.lowercased().trimmingCharacters(in: punctuation)
                guard !word.isEmpty else { return nil }
                let boundary = original.last.map { ",.;:!?".contains($0) } ?? false
                return Token(original: original, word: word, boundaryAfter: boundary)
            }
    }
}

#if DEBUG
extension EarlyIntentDetector {
    /// `-EarlyIntentSelfTest`: table-driven checks with a fixed app resolver. Returns failures.
    @discardableResult
    static func runSelfTest() -> Int {
        let known: Set<String> = ["safari", "vs code", "visual studio code", "youtube", "notes", "mail"]
        let detector = EarlyIntentDetector(resolveApp: { known.contains($0.lowercased()) })

        // (partials in order, expected command from the last one)
        let cases: [([String], EarlyIntent.Command?)] = [
            (["open"], nil),
            (["open saf"], nil),
            (["open safari"], nil),                              // needs stability
            (["open safari", "open safari"], .openApp("safari")),
            (["open Safari and"], .openApp("safari")),
            (["Open VS Code and make a new file"], .openApp("vs code")),
            (["open vs", "open vs code", "open vs code and"], .openApp("vs code")),
            (["open the door and"], nil),
            (["open mail chimp and"], nil),                      // phrase must run to a connector
            (["open mail, then check"], .openApp("mail")),
            (["volume up", "volume up"], .system(.volumeUp)),
            (["volume down and"], .system(.volumeDown)),
            (["volume"], nil),
            (["mute", "mute"], .system(.mute)),
            (["mute the tab"], nil),
            (["unmute and"], .system(.unmute)),
            (["scroll down", "scroll down"], .scroll(.down)),
            (["scroll sideways and"], nil),
            (["press command t and"], .pressKey(.newTab)),
            (["press enter", "press enter"], .pressKey(.returnKey)),
            (["press the button and"], nil),
            (["turn on do not disturb", "turn on do not disturb"], .system(.toggleDoNotDisturb)),
            (["toggle focus and"], .system(.toggleDoNotDisturb)),
            (["turn up the heat and"], nil),
            (["what's the weather"], nil),
            (["type hello and"], nil),                           // TYPE_TEXT never fires early
            (["click submit and"], nil),                         // CLICK never fires early
        ]

        var failures = 0
        for (partials, expected) in cases {
            var previous: EarlyIntent?
            var fired: EarlyIntent?
            for partial in partials {
                fired = detector.detect(partial, previous: previous)
                previous = detector.match(partial)
            }
            let ok = fired?.command == expected
            if !ok { failures += 1 }
            print("[EarlySelfTest] \(ok ? "PASS" : "FAIL") \(partials) → \(fired.map { "\($0.command)" } ?? "nil")" + (ok ? "" : "  expected \(expected.map { "\($0)" } ?? "nil")"))
        }

        let remainders: [(String, EarlyIntent.Command, String?)] = [
            ("Open VS Code and make a new file with a main.py", .openApp("vs code"), "make a new file with a main.py"),
            ("open Safari, then search for Swift", .openApp("safari"), "search for Swift"),
            ("open Safari", .openApp("safari"), ""),
            ("open Notes and type Hello World", .openApp("safari"), nil),   // revised: different command
        ]
        for (text, command, expected) in remainders {
            let fired = EarlyIntent(command: command, consumedWords: 0, followedByMore: true)
            let rest = detector.remainder(of: text, after: fired)
            let ok = rest == expected
            if !ok { failures += 1 }
            print("[EarlySelfTest] \(ok ? "PASS" : "FAIL") remainder(\"\(text)\") → \(rest.map { "\"\($0)\"" } ?? "nil")" + (ok ? "" : "  expected \(expected.map { "\"\($0)\"" } ?? "nil")"))
        }
        print("[EarlySelfTest] \(failures == 0 ? "ALL PASSED" : "\(failures) FAILED") (\(cases.count + remainders.count) cases)")
        return failures
    }
}
#endif
