import Foundation

/// Conversation memory shared by every path: chat replies, single actions, tasks and mid-speech
/// commands all record an exchange here. Claude sees it as chat history, Jev sees a short summary in
/// its state, and it's saved to disk so a relaunch (or a debug rebuild) keeps the thread.
@MainActor
@Observable
final class ConversationManager {
    private(set) var messages: [ChatMessage] = []
    var maxTurns = 20
    /// Exchanges summarized into Jev's state for follow-ups ("search for it there", "do that again").
    var jevTurns = 4

    let systemPrompt = """
    You are a voice assistant running on the user's Mac. Replies are spoken aloud, so keep them \
    short (1–3 sentences), conversational, and free of markdown, lists, and code blocks unless asked. \
    Assistant turns that start with "[Did on the Mac]" record actions you already carried out on the \
    user's Mac (opening apps, clicking, typing); use them to answer questions about what you did. \
    This conversation is saved on the Mac and carries over between sessions until the user clears it.
    """

    static let actionPrefix = "[Did on the Mac]"

    @ObservationIgnored private let storeURL: URL?

    init(storeURL: URL? = ConversationManager.defaultStoreURL) {
        self.storeURL = storeURL
        load()
    }

    func appendUser(_ text: String) {
        append(ChatMessage(role: .user, content: text))
    }

    func appendAssistant(_ text: String) {
        append(ChatMessage(role: .assistant, content: text))
    }

    /// Records a non-chat turn: what the user asked and what the Mac did.
    func recordAction(user: String, did summary: String) {
        appendUser(user)
        appendAssistant("\(Self.actionPrefix) \(summary)")
    }

    /// Messages to send to the LLM: system prompt + trimmed history.
    func context() -> [ChatMessage] {
        [ChatMessage(role: .system, content: systemPrompt)] + messages.suffix(maxTurns * 2)
    }

    /// Context for a new user message that isn't recorded yet.
    func context(adding user: String) -> [ChatMessage] {
        context() + [ChatMessage(role: .user, content: user)]
    }

    /// The last `jevTurns` exchanges as plain lines for Jev's state, or nil when there are none.
    func recentSummary() -> String? {
        let recent = messages.suffix(jevTurns * 2)
        guard !recent.isEmpty else { return nil }
        let lines = recent.map { message in
            let text = message.content.count > 200 ? message.content.prefix(200) + "…" : Substring(message.content)
            return "\(message.role == .user ? "User" : "Assistant"): \(text)"
        }
        return "Earlier in this conversation:\n" + lines.joined(separator: "\n")
    }

    /// Recent user requests, newest first, for text candidates on follow-ups ("search for that again").
    func recentUserTexts(_ count: Int = 2) -> [String] {
        messages.reversed().filter { $0.role == .user }.prefix(count).map(\.content)
    }

    func clear() {
        messages.removeAll()
        save()
    }

    private func append(_ message: ChatMessage) {
        messages.append(message)
        if messages.count > maxTurns * 4 {
            messages.removeFirst(messages.count - maxTurns * 4)
        }
        save()
    }

    // MARK: Persistence

    static var defaultStoreURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appending(path: "VoiceAgent/conversation.json")
    }

    private func load() {
        guard let storeURL, let data = try? Data(contentsOf: storeURL),
              let saved = try? JSONDecoder().decode([ChatMessage].self, from: data) else { return }
        messages = saved
    }

    private func save() {
        guard let storeURL else { return }
        do {
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(messages).write(to: storeURL, options: .atomic)
        } catch {
            DebugLog.print("Conversation", "save failed: \(error)")
        }
    }
}
