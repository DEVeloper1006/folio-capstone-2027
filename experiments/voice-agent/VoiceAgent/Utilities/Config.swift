import Foundation
import Security

/// Central configuration.
///
/// Secrets resolve in order: process environment → `.env` file → Keychain.
/// Non-secret preferences live in `UserDefaults` (surfaced via `@AppStorage` keys below).
enum Config {
    // MARK: Endpoints

    static let openRouterBase = URL(string: "https://openrouter.ai/api/v1")!
    static var systemOneURL: URL { openRouterBase.appending(path: "systemone") }
    static var chatCompletionsURL: URL { openRouterBase.appending(path: "chat/completions") }

    // MARK: Preference keys (@AppStorage)

    enum Key {
        static let jevModel = "jevModel"
        static let chatModel = "chatModel"
        static let extractModel = "extractModel"
        static let voiceIdentifier = "voiceIdentifier"
        static let speakResponses = "speakResponses"
        static let showOverlayPill = "showOverlayPill"
        static let maxTaskSteps = "maxTaskSteps"
    }

    enum Default {
        static let jevModel = "jev-latest"
        static let chatModel = "anthropic/claude-sonnet-5.5"
        static let extractModel = "anthropic/claude-haiku-4.5"
        static let maxTaskSteps = 15
    }

    static var jevModel: String {
        UserDefaults.standard.string(forKey: Key.jevModel) ?? Default.jevModel
    }

    static var chatModel: String {
        UserDefaults.standard.string(forKey: Key.chatModel) ?? Default.chatModel
    }

    static var extractModel: String {
        UserDefaults.standard.string(forKey: Key.extractModel) ?? Default.extractModel
    }

    static var maxTaskSteps: Int {
        let value = UserDefaults.standard.integer(forKey: Key.maxTaskSteps)
        return value > 0 ? value : Default.maxTaskSteps
    }

    // MARK: API key

    static let apiKeyName = "OPENROUTER_API_KEY"

    enum KeySource: String, Sendable {
        case environment = "Environment"
        case dotenv = ".env file"
        case keychain = "Keychain"
    }

    /// Returns the OpenRouter key and where it came from, or nil if none is configured.
    static func openRouterKey() -> (value: String, source: KeySource)? {
        if let env = ProcessInfo.processInfo.environment[apiKeyName], !env.isEmpty {
            return (env, .environment)
        }
        if let dot = DotEnv.load()[apiKeyName], !dot.isEmpty {
            return (dot, .dotenv)
        }
        if let stored = Keychain.read(account: apiKeyName), !stored.isEmpty {
            return (stored, .keychain)
        }
        return nil
    }

    static func saveOpenRouterKey(_ key: String) throws {
        try Keychain.write(key.trimmingCharacters(in: .whitespacesAndNewlines), account: apiKeyName)
    }

    static func clearOpenRouterKey() {
        Keychain.delete(account: apiKeyName)
    }
}

// MARK: - .env

enum DotEnv {
    /// Candidate locations: `$VOICE_AGENT_ENV`, current directory, `~/.config/voice-agent/.env`.
    static var searchPaths: [URL] {
        var paths: [URL] = []
        if let override = ProcessInfo.processInfo.environment["VOICE_AGENT_ENV"] {
            paths.append(URL(fileURLWithPath: override))
        }
        paths.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appending(path: ".env"))
        paths.append(FileManager.default.homeDirectoryForCurrentUser.appending(path: ".config/voice-agent/.env"))
        return paths
    }

    static func load() -> [String: String] {
        for url in searchPaths {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                return parse(text)
            }
        }
        return [:]
    }

    static func parse(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }
}

// MARK: - Keychain

enum Keychain {
    static let service = "com.folio.VoiceAgent"

    enum KeychainError: Error {
        case status(OSStatus)
    }

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func write(_ value: String, account: String) throws {
        delete(account: account)
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
        ]
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.status(status) }
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
