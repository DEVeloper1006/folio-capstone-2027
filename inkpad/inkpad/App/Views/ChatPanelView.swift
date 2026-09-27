import SwiftUI

struct ChatMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let timestamp = Date()
}

struct ChatPanelView: View {
    @Binding var isOpen: Bool
    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isThinking = false

    var body: some View {
        if isOpen {
            VStack(spacing: 0) {
                header
                Divider()
                messageList
                Divider()
                inputBar
            }
            .frame(width: 320)
            .background(FolioTheme.chromeBackground)
            .clipShape(RoundedRectangle(cornerRadius: FolioTheme.cornerRadius))
            .shadow(color: FolioTheme.shadow, radius: 12, y: 4)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    private var header: some View {
        HStack {
            Text("Chat")
                .font(FolioTheme.uiFont(size: 16, weight: .semibold))
            Spacer()
            Button {
                withAnimation { isOpen = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FolioTheme.muted)
            }
        }
        .padding()
    }

    private var messageList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if messages.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .font(.system(size: 28))
                            .foregroundStyle(FolioTheme.dim)
                        Text("Ask about this page")
                            .font(FolioTheme.uiFont(size: 13))
                            .foregroundStyle(FolioTheme.muted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }

                ForEach(messages) { msg in
                    chatBubble(msg)
                }

                if isThinking {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Thinking...")
                            .font(FolioTheme.uiFont(size: 12))
                            .foregroundStyle(FolioTheme.dim)
                    }
                    .padding(.leading, 8)
                }
            }
            .padding()
        }
        .frame(maxHeight: 400)
    }

    private func chatBubble(_ msg: ChatMessage) -> some View {
        HStack {
            if msg.isUser { Spacer(minLength: 40) }
            Text(msg.text)
                .font(FolioTheme.uiFont(size: 14))
                .foregroundStyle(msg.isUser ? .white : FolioTheme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(msg.isUser ? FolioTheme.accent : FolioTheme.panel)
                )
            if !msg.isUser { Spacer(minLength: 40) }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("Ask a question...", text: $inputText)
                .font(FolioTheme.uiFont(size: 14))
                .textFieldStyle(.plain)
                .onSubmit { sendMessage() }

            Button {
                sendMessage()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(inputText.isEmpty ? FolioTheme.dim : FolioTheme.accent)
            }
            .disabled(inputText.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        messages.append(ChatMessage(text: text, isUser: true))
        inputText = ""
        isThinking = true

        Task {
            try? await Task.sleep(for: .seconds(1.5))
            isThinking = false
            let reply = mockReply(for: text)
            messages.append(ChatMessage(text: reply, isUser: false))
        }
    }

    private func mockReply(for question: String) -> String {
        if question.lowercased().contains("row") {
            return "Row 2 should have a leading 0 after the operation R2 \u{2190} R2 + 1.5R1. Check your arithmetic."
        }
        if question.lowercased().contains("step") {
            return "The next step would be to eliminate the entry in row 3, column 1."
        }
        return "That's a good question! In this context, try reviewing the previous row operation."
    }
}
