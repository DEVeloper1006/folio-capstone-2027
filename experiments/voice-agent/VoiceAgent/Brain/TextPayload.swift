import Foundation

/// Candidate strings for TYPE_TEXT, extracted from the user's own words by code.
///
/// Jev picks one of these as the `text_payload` choice, so nothing a model generates can ever be
/// typed: the payload is always a verbatim span of the transcript.
enum TextPayload {
    static let maxCandidates = 10

    /// Phrases that introduce the literal text, longest first so "that says" wins over "says".
    /// "search up", "called" and "named" come from live requests ("search up yes theory videos",
    /// "a file called main.py") that otherwise only offered the whole utterance.
    static let triggers = [
        "with the text", "that says", "which says", "reply with", "search for", "search up", "look up",
        "look for", "called", "named", "titled", "saying", "says", "type", "write", "enter", "put",
        "dictate", "search", "for",
    ]

    /// Trailing location phrases trimmed off a tail: "hello world into the search field" → "hello world".
    /// " and " splits "called main.py and write hello world" → "main.py"; the uncut tail is still offered.
    static let locationCuts = [" into the ", " in the ", " on the ", " into ", " in ", " and press ", " then ", " and "]

    static func candidates(from transcript: String) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()

        func add(_ raw: String) {
            let phrase = clean(raw)
            guard !phrase.isEmpty, ordered.count < maxCandidates, seen.insert(phrase.lowercased()).inserted else { return }
            ordered.append(phrase)
        }

        quotedSpans(in: transcript).forEach(add)

        let lower = transcript.lowercased()
        for trigger in triggers {
            guard let range = lower.range(of: "\\b\(trigger)\\b", options: .regularExpression) else { continue }
            let tail = String(transcript[range.upperBound...])
            for cut in locationCuts {
                if let cutRange = tail.lowercased().range(of: cut) {
                    add(String(tail[..<cutRange.lowerBound]))
                }
            }
            add(tail)
        }

        add(transcript)
        return ordered
    }

    /// Candidates from this transcript first, then from earlier requests, so a follow-up ("search for
    /// that on YouTube too") can still type a phrase the user said in a previous turn. Still verbatim.
    static func candidates(from transcript: String, followingUp earlier: [String]) -> [String] {
        var ordered = candidates(from: transcript)
        var seen = Set(ordered.map { $0.lowercased() })
        for text in earlier {
            for phrase in candidates(from: text).dropLast() where ordered.count < maxCandidates {
                // dropLast: skip the earlier request as a whole; only its extracted phrases carry over.
                if seen.insert(phrase.lowercased()).inserted { ordered.append(phrase) }
            }
        }
        return ordered
    }

    /// `type "hello world"`, `write ‘hi’`, `“note to self”`.
    static func quotedSpans(in text: String) -> [String] {
        let pattern = #"[\"“'‘]([^\"“”'‘’]{1,200})[\"”'’]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range(at: 1), in: text).map { String(text[$0]) }
        }
    }

    /// Criteria for the Jev `text_payload` question, keyed by the phrase itself.
    static func criteria(_ candidates: [String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: candidates.map { ($0, "Type exactly: \($0)") })
    }

    static func clean(_ phrase: String) -> String {
        var text = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        // Leading filler left over from the trigger ("type: hello", "saying that hello").
        for prefix in [":", "that ", "the text "] where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return text.trimmingCharacters(in: CharacterSet(charactersIn: " .,!?\"“”'‘’"))
    }
}
