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
    /// Words of the transcript consumed up to the end of this command, counted from the start of
    /// the transcript ("open vs code" → 3; "open safari and open notes" → 6 for the second one).
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
/// Leading filler ("please", "can you", "and then") is skipped, and natural verbs work ("open up",
/// "pull up", "launch", "go to"). Commands chain: `match(_:after:)` starts after the words an earlier
/// command consumed, so "open up Safari and open up YouTube and …" fires both, one after the other.
///
/// Never produces TASK, CHAT, TYPE_TEXT or CLICK: those need the whole utterance.
@MainActor
struct EarlyIntentDetector {
    /// Returns true if an app or website with this spoken name can be opened.
    var resolveApp: @MainActor (String) -> Bool

    static let connectors: Set<String> = ["and", "then", "also"]
    static let maxAppNameWords = 4

    /// Skipped before a command. Connectors are included so a chained command can follow "and then".
    static let fillers: [[String]] = [
        ["go", "ahead", "and"], ["can", "you"], ["could", "you"], ["would", "you"], ["will", "you"],
        ["please"], ["okay"], ["ok"], ["hey"], ["now"], ["and"], ["then"], ["also"],
    ]

    /// Verbs that open an app or website, longest first so "open up" wins over "open".
    static let openVerbs: [[String]] = [
        ["open", "up"], ["pull", "up"], ["bring", "up"], ["switch", "to"], ["go", "to"],
        ["open"], ["launch"], ["start"],
    ]

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

    /// Matches `text` from word `offset` on and applies the stability rule against the previous
    /// partial's match at the same offset.
    func detect(_ text: String, after offset: Int = 0, previous: EarlyIntent?) -> EarlyIntent? {
        guard let match = match(text, after: offset) else { return nil }
        return match.followedByMore || match.command == previous?.command ? match : nil
    }

    /// Match only (no stability rule): the command starting at word `offset` of `text`, after any
    /// leading filler.
    func match(_ text: String, after offset: Int = 0) -> EarlyIntent? {
        let tokens = Self.tokens(text)
        let words = tokens.map(\.word)
        guard offset < words.count else { return nil }

        // Skip filler ("please", "can you", "and then") before the verb.
        var start = offset
        while let filler = Self.fillers.first(where: { Self.hasPrefix(words, $0, at: start) }) {
            start += filler.count
        }
        guard start < words.count else { return nil }

        // Span: words from `from` up to (not including) a connector or a punctuation boundary.
        func span(from: Int) -> (words: [String], end: Int) {
            var end = from
            while end < tokens.count, !Self.connectors.contains(tokens[end].word) {
                end += 1
                if tokens[end - 1].boundaryAfter { break }
            }
            return (Array(words[min(from, end)..<end]), end)
        }
        func intent(_ command: EarlyIntent.Command, consumed: Int) -> EarlyIntent {
            EarlyIntent(command: command, consumedWords: consumed, followedByMore: consumed < tokens.count)
        }
        func rest(after phrase: [String]) -> (words: [String], end: Int)? {
            Self.hasPrefix(words, phrase, at: start) ? span(from: start + phrase.count) : nil
        }

        for verb in Self.openVerbs {
            guard case let (name, end)? = rest(after: verb), !name.isEmpty, name.count <= Self.maxAppNameWords else { continue }
            let spoken = name.joined(separator: " ")
            if resolveApp(spoken) { return intent(.openApp(spoken), consumed: end) }
        }

        if case let (name, end)? = rest(after: ["press"]), let chord = Self.keyNames[name.joined(separator: " ")] {
            return intent(.pressKey(chord), consumed: end)
        }

        if case let (direction, end)? = rest(after: ["scroll"]) {
            switch direction {
            case ["up"]: return intent(.scroll(.up), consumed: end)
            case ["down"]: return intent(.scroll(.down), consumed: end)
            default: break
            }
        }

        // "volume up", "turn the volume up", "turn up the volume", "turn it down".
        for phrase in [["volume"], ["turn", "the", "volume"], ["turn", "volume"], ["turn", "it"], ["turn"]] {
            guard case let (tail, end)? = rest(after: phrase) else { continue }
            let kind: ActionKind? = switch tail {
            case ["up"], ["up", "the", "volume"], ["the", "volume", "up"]: .volumeUp
            case ["down"], ["down", "the", "volume"], ["the", "volume", "down"]: .volumeDown
            default: nil
            }
            if let kind { return intent(.system(kind), consumed: end) }
        }

        if ["mute", "unmute"].contains(words[start]) {
            let (tail, end) = span(from: start)
            if tail.count == 1 { return intent(.system(words[start] == "mute" ? .mute : .unmute), consumed: end) }
        }

        for phrase in [["turn", "on"], ["turn", "off"], ["toggle"]] {
            guard case let (tail, end)? = rest(after: phrase) else { continue }
            if ["do not disturb", "dnd", "focus"].contains(tail.joined(separator: " ")) {
                return intent(.system(.toggleDoNotDisturb), consumed: end)
            }
        }
        return nil
    }

    /// What's left of `text` after commands that already ran, in order, or nil if `text` no longer
    /// matches them (the recognizer revised the words). Leading connectors are dropped, and the
    /// remainder keeps its original casing ("…and type Hello" stays "type Hello").
    func remainder(of text: String, after fired: [EarlyIntent]) -> String? {
        var offset = 0
        for command in fired {
            guard let match = match(text, after: offset), match.command == command.command else { return nil }
            offset = match.consumedWords
        }
        var rest = Self.tokens(text).dropFirst(offset)
        while let first = rest.first, Self.connectors.contains(first.word) {
            rest = rest.dropFirst()
        }
        return rest.map(\.original).joined(separator: " ")
    }

    private static func hasPrefix(_ words: [String], _ phrase: [String], at start: Int) -> Bool {
        start + phrase.count <= words.count && Array(words[start..<start + phrase.count]) == phrase
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

        // (partials in order, every command expected to fire across them). Mirrors VoiceSession:
        // after a fire, matching continues after the consumed words.
        let cases: [([String], [EarlyIntent.Command])] = [
            (["open"], []),
            (["open saf"], []),
            (["open safari"], []),                               // needs stability
            (["open safari", "open safari"], [.openApp("safari")]),
            (["open Safari and"], [.openApp("safari")]),
            (["Open VS Code and make a new file"], [.openApp("vs code")]),
            (["open vs", "open vs code", "open vs code and"], [.openApp("vs code")]),
            (["open the door and"], []),
            (["open mail chimp and"], []),                       // phrase must run to a connector
            (["open mail, then check"], [.openApp("mail")]),
            (["volume up", "volume up"], [.system(.volumeUp)]),
            (["volume down and"], [.system(.volumeDown)]),
            (["volume"], []),
            (["mute", "mute"], [.system(.mute)]),
            (["mute the tab"], []),
            (["unmute and"], [.system(.unmute)]),
            (["scroll down", "scroll down"], [.scroll(.down)]),
            (["scroll sideways and"], []),
            (["press command t and"], [.pressKey(.newTab)]),
            (["press enter", "press enter"], [.pressKey(.returnKey)]),
            (["press the button and"], []),
            (["turn on do not disturb", "turn on do not disturb"], [.system(.toggleDoNotDisturb)]),
            (["toggle focus and"], [.system(.toggleDoNotDisturb)]),
            (["turn up the heat and"], []),
            (["what's the weather"], []),
            (["type hello and"], []),                            // TYPE_TEXT never fires early
            (["click submit and"], []),                          // CLICK never fires early
            // Natural phrasing, taken from live logs (2026-09-30).
            (["Open up YouTube", "Open up YouTube and search"], [.openApp("youtube")]),
            (["Please open up YouTube and then search up"], [.openApp("youtube")]),
            (["can you pull up notes and"], [.openApp("notes")]),
            (["go to youtube and"], [.openApp("youtube")]),
            (["turn the volume up and"], [.system(.volumeUp)]),
            (["turn it down and"], [.system(.volumeDown)]),
            (["Open up a file and VS code called"], []),         // "a file" isn't an app
            (["Play some logic song on Spotify"], []),
            // Chained commands fire one after another as the sentence grows.
            (["Open up Safari and", "Open up Safari and open up YouTube", "Open up Safari and open up YouTube and then search"],
             [.openApp("safari"), .openApp("youtube")]),
            (["open notes and mute and"], [.openApp("notes"), .system(.mute)]),
        ]

        var failures = 0
        for (partials, expected) in cases {
            var previous: EarlyIntent?
            var offset = 0
            var fired: [EarlyIntent.Command] = []
            for partial in partials {
                // Keep matching at the new offset within the same partial until nothing new fires.
                while let hit = detector.detect(partial, after: offset, previous: previous) {
                    fired.append(hit.command)
                    offset = hit.consumedWords
                    previous = nil
                }
                previous = detector.match(partial, after: offset)
            }
            let ok = fired == expected
            if !ok { failures += 1 }
            print("[EarlySelfTest] \(ok ? "PASS" : "FAIL") \(partials) → \(fired)" + (ok ? "" : "  expected \(expected)"))
        }

        let remainders: [(String, [EarlyIntent.Command], String?)] = [
            ("Open VS Code and make a new file with a main.py", [.openApp("vs code")], "make a new file with a main.py"),
            ("open Safari, then search for Swift", [.openApp("safari")], "search for Swift"),
            ("open Safari", [.openApp("safari")], ""),
            ("open Notes and type Hello World", [.openApp("safari")], nil),   // revised: different command
            ("Please open up YouTube and then search up yes theory videos", [.openApp("youtube")], "search up yes theory videos"),
            ("Open up Safari and open up YouTube and then search up history videos",
             [.openApp("safari"), .openApp("youtube")], "search up history videos"),
        ]
        for (text, commands, expected) in remainders {
            let fired = commands.map { EarlyIntent(command: $0, consumedWords: 0, followedByMore: true) }
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
