import Foundation

/// DEBUG-only console and file logging. Compiles to no-ops in Release.
enum DebugLog {
    /// `experiments/voice-agent/logs/`, resolved from this source file (dev builds only).
    /// `logs/.gitignore` keeps everything in it out of git: it holds transcripts and screen text.
    static let logsDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // Utilities/
        .deletingLastPathComponent()   // VoiceAgent/
        .deletingLastPathComponent()   // experiments/voice-agent/
        .appending(path: "logs")

    static let jevRequestsFile = logsDirectory.appending(path: "jev_requests.jsonl")

    private static let start = ContinuousClock.now

    /// `[Tag +1.234s] message`, with seconds since the first log line so timing across components is visible.
    static func print(_ tag: String, _ message: @autoclosure () -> String) {
        #if DEBUG
        let elapsed = ContinuousClock.now - start
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        Swift.print("[\(tag) +\(String(format: "%.3f", seconds))s] \(message())")
        #endif
    }

    /// First `limit` characters on one line, with newlines shown as ⏎.
    static func truncated(_ text: String, limit: Int = 500) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ⏎ ")
        return flat.count > limit ? String(flat.prefix(limit)) + "… (\(flat.count) chars)" : flat
    }

    /// Appends one JSON object as a line to `file`.
    static func appendJSONLine(_ object: [String: Any], to file: URL) {
        #if DEBUG
        guard JSONSerialization.isValidJSONObject(object),
              var data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: file) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: file)
        }
        #endif
    }
}
