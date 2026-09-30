import AppKit
import SwiftUI

/// Floating status indicator. One glass circle (state icon) plus an optional detail capsule
/// (waveform or label), both in one `GlassEffectContainer` so they morph via `glassEffectID`.
///
/// idle (dim) → listening (breathing mic + waveform) → thinking (spinner) → executing (action icon)
/// → done (checkmark) | error (x mark). Each state has its own glass tint (`State.glass`).
struct OverlayPill: View {
    @Environment(VoiceSession.self) private var session
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                icon
                    .frame(width: 36, height: 36)
                    .background(session.state.fill, in: .circle)
                    .glassEffect(session.state.glass, in: .circle)
                    .glassEffectID("icon", in: glass)

                if session.state == .listening {
                    Waveform(level: session.recognizer.level)
                        .foregroundStyle(session.state.iconStyle)
                        .frame(width: 64, height: 18)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(session.state.fill, in: .capsule)
                        .glassEffect(session.state.glass, in: .capsule)
                        .glassEffectID("detail", in: glass)
                        .glassEffectTransition(.matchedGeometry)
                } else if showsLabel {
                    Text(label)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(session.state.iconStyle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .contentTransition(.opacity)
                        .frame(maxWidth: 280)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(session.state.fill, in: .capsule)
                        .glassEffect(session.state.glass, in: .capsule)
                        .glassEffectID("detail", in: glass)
                        .glassEffectTransition(.matchedGeometry)
                }
            }
            .padding(6)
        }
        .opacity(session.state == .idle ? 0.55 : 1)
        .animation(.bouncy(duration: 0.35), value: session.state)
        .contentShape(.capsule)
        .onTapGesture { session.toggle() }
        .fixedSize()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Voice Agent: \(session.state.label)")
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var icon: some View {
        if session.state == .thinking {
            ProgressView()
                .controlSize(.small)
                .tint(.white)
                .transition(.scale.combined(with: .opacity))
        } else {
            Image(systemName: session.state.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(session.state.iconStyle)
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.breathe, isActive: session.state == .listening && !reduceMotion)
                .transition(.scale.combined(with: .opacity))
        }
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

extension VoiceSession.State {
    /// A distinct glass tint per state, shared by the pill and the menu bar dropdown.
    /// Strong enough to read over dark and busy backdrops; idle stays near-neutral.
    var glass: Glass {
        switch self {
        case .idle: .regular.tint(.gray.opacity(0.15))
        case .listening: .regular.tint(.blue.opacity(0.7))
        case .thinking: .regular.tint(.indigo.opacity(0.65))
        case .executing: .regular.tint(.orange.opacity(0.7))
        case .speaking: .regular.tint(.teal.opacity(0.65))
        case .done: .regular.tint(.green.opacity(0.65))
        case .error: .regular.tint(.red.opacity(0.7))
        }
    }

    /// State color drawn inside the glass shape. `Glass.tint` alone doesn't show up in the
    /// borderless non-activating pill panel (checked with screenshots), so the color is also
    /// laid in as translucent content that the glass renders around.
    var fill: Color {
        switch self {
        case .idle: .clear
        case .listening: .blue.opacity(0.55)
        case .thinking: .indigo.opacity(0.55)
        case .executing: .orange.opacity(0.55)
        case .speaking: .teal.opacity(0.5)
        case .done: .green.opacity(0.5)
        case .error: .red.opacity(0.55)
        }
    }

    /// Icon color: muted when idle, white on the tinted glass of every other state.
    var iconStyle: Color {
        switch self {
        case .idle: .secondary
        default: .white
        }
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
