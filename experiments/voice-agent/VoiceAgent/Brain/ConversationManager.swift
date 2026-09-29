import Foundation

/// Chat history for the conversation panel and the LLM context window.
@MainActor
@Observable
final class ConversationManager {
    private(set) var messages: [ChatMessage] = []
    var maxTurns = 20

    let systemPrompt = """
    You are a voice assistant running on the user's Mac. Replies are spoken aloud, so keep them \
    short (1–3 sentences), conversational, and free of markdown, lists, and code blocks unless asked.
    """

    func appendUser(_ text: String) {
        append(ChatMessage(role: .user, content: text))
    }

    func appendAssistant(_ text: String) {
        append(ChatMessage(role: .assistant, content: text))
    }

    /// Messages to send to the LLM: system prompt + trimmed history.
    func context() -> [ChatMessage] {
        [ChatMessage(role: .system, content: systemPrompt)] + messages.suffix(maxTurns * 2)
    }

    func clear() {
        messages.removeAll()
    }

    private func append(_ message: ChatMessage) {
        messages.append(message)
        if messages.count > maxTurns * 4 {
            messages.removeFirst(messages.count - maxTurns * 4)
        }
    }
}
