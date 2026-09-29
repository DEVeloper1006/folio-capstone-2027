import AppKit
import SwiftUI

/// Floating status indicator. Glass capsules morph between states via `glassEffectID`.
struct OverlayPill: View {
    @Environment(VoiceSession.self) private var session
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                icon
                    .glassEffect(session.state.glass, in: .circle)
                    .glassEffectID("icon", in: glass)

                if session.state == .listening {
                    Waveform(level: session.recognizer.level)
                        .frame(width: 64, height: 18)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .glassEffect(session.state.glass, in: .capsule)
                        .glassEffectID("detail", in: glass)
                } else if showsLabel {
                    Text(label)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: 280)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .glassEffect(session.state.glass, in: .capsule)
                        .glassEffectID("detail", in: glass)
                }
            }
            .padding(6)
        }
        .animation(.bouncy(duration: 0.35), value: session.state)
        .contentShape(.capsule)
        .onTapGesture { session.toggle() }
        .fixedSize()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Voice Agent: \(session.state.label)")
        .accessibilityAddTraits(.isButton)
    }

    private var icon: some View {
        Image(systemName: session.state.symbol)
            .font(.system(size: 15, weight: .semibold))
            .contentTransition(.symbolEffect(.replace))
            .symbolEffect(.pulse, isActive: session.state == .thinking)
            .frame(width: 36, height: 36)
    }

    private var showsLabel: Bool {
        switch session.state {
        case .idle: false
        default: true
        }
    }

    private var label: String {
        if case .thinking = session.state, !session.transcript.isEmpty {
            return "“\(session.transcript)”"
        }
        return session.state.label
    }
}

/// Minimal level meter for the listening state.
private struct Waveform: View {
    var level: Float
    private let bars = 7

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<bars, id: \.self) { index in
                let falloff = 1 - abs(Double(index) - Double(bars - 1) / 2) / Double(bars)
                Capsule()
                    .frame(width: 3, height: max(3, 18 * CGFloat(level) * falloff))
            }
        }
        .foregroundStyle(.primary)
        .animation(.easeOut(duration: 0.08), value: level)
    }
}

// MARK: - Panel

/// Borderless, non-activating, always-on-top panel. Never steals focus from the app being controlled,
/// which matters because `AXTreeCrawler` reads the *focused* application.
final class OverlayPillPanel: NSPanel {
    init(session: VoiceSession) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = true

        let hosting = NSHostingView(rootView: OverlayPill().environment(session))
        hosting.sizingOptions = []
        contentView = hosting
        positionTopCenter()
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    private func positionTopCenter() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(x: visible.midX - frame.width / 2, y: visible.maxY - frame.height - 8)
        setFrameOrigin(origin)
    }
}
