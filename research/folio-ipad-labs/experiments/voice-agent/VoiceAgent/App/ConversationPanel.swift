import AppKit
import SwiftUI

/// Chat transcript with glass chrome. Messages are content, so they stay un-glassed;
/// the header and composer float over them as glass controls.
struct ConversationPanel: View {
    @Environment(VoiceSession.self) private var session
    var onClose: () -> Void = {}

    @State private var draft = ""
    @FocusState private var composerFocused: Bool
    @Namespace private var glass

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if session.conversation.messages.isEmpty {
                        emptyState
                    }
                    ForEach(session.conversation.messages) { message in
                        MessageRow(message: message)
                            .id(message.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollEdgeEffectStyle(.soft, for: .all)
            .background {
                // Extends softly under the floating glass bars instead of a hard cut-off.
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.08), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .backgroundExtensionEffect()
            }
            .safeAreaInset(edge: .top, spacing: 0) { header }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
            .onChange(of: session.conversation.messages.last?.id) { _, id in
                guard let id else { return }
                withAnimation(.smooth) { proxy.scrollTo(id, anchor: .bottom) }
            }
        }
        .frame(minWidth: 360, idealWidth: 400, minHeight: 440, idealHeight: 560)
        .animation(.smooth, value: session.state)
    }

    // MARK: Chrome

    private var header: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Label(session.state.label, systemImage: session.state.symbol)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .contentTransition(.symbolEffect(.replace))
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .glassEffect(session.state.glass, in: .capsule)
                    .glassEffectID("status", in: glass)

                Spacer()

                Button("Clear", systemImage: "trash") { session.conversation.clear() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .tint(.clear)
                    .disabled(session.conversation.messages.isEmpty)
                    .glassEffectID("clear", in: glass)

                Button("Close", systemImage: "xmark") { onClose() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .tint(.clear)
                    .keyboardShortcut(.cancelAction)
                    .glassEffectID("close", in: glass)
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 6)
        }
    }

    private var composer: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                TextField("Ask or tell your Mac…", text: $draft)
                    .textFieldStyle(.plain)
                    .focused($composerFocused)
                    .onSubmit(send)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .glassEffect(.regular, in: .capsule)
                    .glassEffectID("field", in: glass)

                if draft.isEmpty {
                    Button {
                        session.toggle()
                    } label: {
                        Image(systemName: session.state == .listening ? "stop.fill" : "mic.fill")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel(session.state == .listening ? "Stop listening" : "Start listening")
                    .glassEffectID("action", in: glass)
                } else {
                    Button(action: send) {
                        Image(systemName: "arrow.up")
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel("Send")
                    .glassEffectID("action", in: glass)
                }
            }
            .controlSize(.large)
            .padding(12)
            .animation(.bouncy(duration: 0.3), value: draft.isEmpty)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Press ⌥Space and start talking, or type below.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    private func send() {
        let text = draft
        draft = ""
        session.submit(text)
    }
}

private struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 40) }
            Text(message.content)
                .textSelection(.enabled)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    message.role == .user ? AnyShapeStyle(Color.accentColor.opacity(0.18)) : AnyShapeStyle(.quaternary),
                    in: .rect(cornerRadius: 14)
                )
            if message.role != .user { Spacer(minLength: 40) }
        }
    }
}

// MARK: - Window

/// Floating utility panel that can take keyboard focus for the composer but doesn't
/// hide when the user switches back to the app they're controlling.
final class ConversationPanelWindow: NSPanel {
    private let onClose: () -> Void

    init(session: VoiceSession, onClose: @escaping () -> Void) {
        self.onClose = onClose
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 560),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        title = "Conversation"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        standardWindowButton(.closeButton)?.isHidden = true

        contentView = NSHostingView(
            rootView: ConversationPanel { [weak self] in self?.close() }
                .environment(session)
        )
        center()
        setFrameAutosaveName("ConversationPanel")
    }

    override var canBecomeKey: Bool { true }

    func present() {
        makeKeyAndOrderFront(nil)
    }

    override func close() {
        super.close()
        onClose()
    }
}
