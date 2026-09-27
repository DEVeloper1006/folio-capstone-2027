import SwiftUI
import WebKit

enum ChatAnchor: Equatable {
    case page
    case step(Int)
}

struct ChatPanelView: View {
    @Binding var isOpen: Bool
    var sessionMode: SessionMode = .coach
    var mathMode: MathMode = .linalg
    var anchor: ChatAnchor = .page

    @State private var messages: [ChatUIMessage] = []
    @State private var inputText = ""
    @State private var isThinking = false
    @State private var socraticLevel: SocraticLevel = .nudge
    @State private var showInkChip = false
    @State private var inkChipLatex = ""
    @State private var pendingReveal = false

    private let chatService: ChatService = MockChatService()

    var body: some View {
        if isOpen {
            VStack(spacing: 0) {
                header
                Divider()
                messageList
                Divider()
                if showInkChip { inkChipBar }
                latexPreview
                inputBar
            }
            .frame(width: 340)
            .background(FolioTheme.chromeBackground)
            .clipShape(RoundedRectangle(cornerRadius: FolioTheme.cornerRadius))
            .shadow(color: FolioTheme.shadow, radius: 12, y: 4)
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: anchor == .page ? "text.bubble" : "bubble.left.and.text.bubble")
                    .font(.system(size: 14))
                    .foregroundStyle(FolioTheme.accent)
                Text(anchor == .page ? "Page Chat" : "Step Thread")
                    .font(FolioTheme.uiFont(size: 15, weight: .semibold))
                Spacer()
                Button { withAnimation { isOpen = false } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(FolioTheme.muted)
                }
            }

            if sessionMode != .solo {
                socraticDial
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var socraticDial: some View {
        HStack(spacing: 0) {
            ForEach(allowedLevels, id: \.self) { level in
                Button {
                    socraticLevel = level
                } label: {
                    Text(level.label)
                        .font(FolioTheme.uiFont(size: 11, weight: socraticLevel == level ? .bold : .regular))
                        .foregroundStyle(socraticLevel == level ? FolioTheme.accent : FolioTheme.muted)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            socraticLevel == level
                            ? FolioTheme.accentFill
                            : Color.clear
                        )
                        .clipShape(Capsule())
                }
            }
        }
        .padding(3)
        .background(FolioTheme.panel.clipShape(Capsule()))
    }

    private var allowedLevels: [SocraticLevel] {
        switch sessionMode {
        case .solo: []
        case .check: [.hint]
        case .coach: [.hint, .nudge, .explain, .solve]
        }
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if messages.isEmpty {
                        emptyState
                    }
                    ForEach(messages) { msg in
                        chatBubble(msg)
                            .id(msg.id)
                    }
                    if isThinking { thinkingIndicator }
                }
                .padding(12)
            }
            .frame(maxHeight: 380)
            .onChange(of: messages.count) {
                if let last = messages.last {
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var emptyState: some View {
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

    private func chatBubble(_ msg: ChatUIMessage) -> some View {
        VStack(alignment: msg.isUser ? .trailing : .leading, spacing: 4) {
            if msg.isRevealCard {
                revealCard(msg)
            } else if msg.hasLatex {
                latexBubble(msg)
            } else {
                plainBubble(msg)
            }
        }
        .frame(maxWidth: .infinity, alignment: msg.isUser ? .trailing : .leading)
    }

    private func plainBubble(_ msg: ChatUIMessage) -> some View {
        Text(msg.text)
            .font(FolioTheme.uiFont(size: 14))
            .foregroundStyle(msg.isUser ? .white : FolioTheme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(msg.isUser ? FolioTheme.accent : FolioTheme.panel)
            )
            .frame(maxWidth: 260, alignment: msg.isUser ? .trailing : .leading)
    }

    private func latexBubble(_ msg: ChatUIMessage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MathRendererView(
                html: MathRenderer.renderChatMessage(msg.text, isAI: !msg.isUser),
                minHeight: 50
            )
            .frame(height: max(60, CGFloat(msg.text.count / 3)))
        }
        .frame(maxWidth: 280)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(msg.isUser ? FolioTheme.accent.opacity(0.12) : FolioTheme.panel)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func revealCard(_ msg: ChatUIMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: msg.revealMatch == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(msg.revealMatch == true ? FolioTheme.statusOK : FolioTheme.statusError)
                Text(msg.revealMatch == true ? "Match!" : "Mismatch")
                    .font(FolioTheme.uiFont(size: 14, weight: .semibold))
            }
            MathRendererView(html: MathRenderer.renderChatMessage(msg.text, isAI: true), minHeight: 40)
                .frame(height: 50)
        }
        .padding(12)
        .frame(maxWidth: 280)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(FolioTheme.accentFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(FolioTheme.accent, lineWidth: 1)
                )
        )
    }

    private var thinkingIndicator: some View {
        HStack(spacing: 4) {
            ProgressView().scaleEffect(0.7)
            Text("Thinking...")
                .font(FolioTheme.uiFont(size: 12))
                .foregroundStyle(FolioTheme.dim)
        }
        .padding(.leading, 8)
    }

    // MARK: - Ink Chip

    private var inkChipBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "lasso")
                .font(.system(size: 13))
                .foregroundStyle(FolioTheme.accent)
            TextField("Recognized LaTeX", text: $inkChipLatex)
                .font(.system(size: 13, design: .monospaced))
                .textFieldStyle(.plain)
            Button {
                if !inkChipLatex.isEmpty {
                    sendMessage(text: "$\(inkChipLatex)$", hasLatex: true)
                }
                showInkChip = false
                inkChipLatex = ""
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(FolioTheme.accent)
            }
            Button {
                showInkChip = false
                inkChipLatex = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(FolioTheme.dim)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(FolioTheme.accentFill)
    }

    // MARK: - LaTeX Preview

    private var latexPreview: some View {
        Group {
            if inputText.contains("$") || inputText.contains("\\") {
                MathRendererView(
                    html: MathRenderer.renderChatMessage(inputText, isAI: false),
                    minHeight: 28
                )
                .frame(height: 32)
                .padding(.horizontal, 12)
                .background(FolioTheme.panel.opacity(0.5))
            }
        }
    }

    // MARK: - Input

    private var inputBar: some View {
        HStack(spacing: 8) {
            Button {
                let recognized = MockRecognitionService().recognize(strokeData: Data())
                inkChipLatex = recognized
                showInkChip = true
            } label: {
                Image(systemName: "lasso.badge.sparkles")
                    .font(.system(size: 18))
                    .foregroundStyle(FolioTheme.accent)
            }

            TextField("Ask a question...", text: $inputText)
                .font(FolioTheme.uiFont(size: 14))
                .textFieldStyle(.plain)
                .onSubmit { sendUserMessage() }

            Button { sendUserMessage() } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(inputText.isEmpty ? FolioTheme.dim : FolioTheme.accent)
            }
            .disabled(inputText.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Actions

    private func sendUserMessage() {
        let text = inputText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let hasLatex = text.contains("$") || text.contains("\\")
        sendMessage(text: text, hasLatex: hasLatex)
        inputText = ""
    }

    private func sendMessage(text: String, hasLatex: Bool) {
        messages.append(ChatUIMessage(text: text, isUser: true, hasLatex: hasLatex))
        isThinking = true

        Task {
            let reply = await chatService.reply(to: text, level: socraticLevel, mode: mathMode, context: nil)
            isThinking = false

            let replyHasLatex = reply.latex != nil || (reply.text.contains("$") || reply.text.contains("\\"))
            messages.append(ChatUIMessage(
                text: reply.text, isUser: false, hasLatex: replyHasLatex,
                isRevealCard: reply.isRevealPrompt
            ))

            if reply.isRevealPrompt {
                pendingReveal = true
            }
        }
    }

    func attachInkSelection(strokeData: Data) {
        let recognized = MockRecognitionService().recognize(strokeData: strokeData)
        inkChipLatex = recognized
        showInkChip = true
    }
}

// MARK: - Chat UI Model

struct ChatUIMessage: Identifiable {
    let id = UUID()
    let text: String
    let isUser: Bool
    let hasLatex: Bool
    let isRevealCard: Bool
    let revealMatch: Bool?
    let timestamp = Date()

    init(text: String, isUser: Bool, hasLatex: Bool = false, isRevealCard: Bool = false, revealMatch: Bool? = nil) {
        self.text = text
        self.isUser = isUser
        self.hasLatex = hasLatex
        self.isRevealCard = isRevealCard
        self.revealMatch = revealMatch
    }
}
