import AppKit
import SwiftUI

@main
struct VoiceAgentApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent()
                .environment(appDelegate.session)
                .environment(appDelegate.panels)
        } label: {
            MenuBarLabel(session: appDelegate.session)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appDelegate.session)
                .environment(appDelegate.session.permissions)
        }
    }
}

// MARK: - App delegate

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let session = VoiceSession()
    lazy var panels = PanelCoordinator(session: session)

    func applicationDidFinishLaunching(_ notification: Notification) {
        session.registerHotKeys()
        if UserDefaults.standard.object(forKey: Config.Key.showOverlayPill) as? Bool ?? true {
            panels.showPill()
        }
        #if DEBUG
        setvbuf(stdout, nil, _IOLBF, 0)   // debug logs reach a redirected stdout promptly
        let args = ProcessInfo.processInfo.arguments
        if let flag = args.firstIndex(of: "-PillState"), args.indices.contains(flag + 1) {
            session.debugPin(args[flag + 1])
            return   // skip permission prompts in visual-check mode
        }
        // Drives the full pipeline without the mic: `-Utterance "open youtube"`.
        if let flag = args.firstIndex(of: "-Utterance"), args.indices.contains(flag + 1) {
            session.submit(args[flag + 1])
            return
        }
        #endif
        Task {
            await session.permissions.requestAll()
            session.showAccessibilityHintIfNeeded()
        }
    }
}

/// Owns the AppKit panels that host SwiftUI views (overlay pill, conversation).
@MainActor
@Observable
final class PanelCoordinator {
    private let session: VoiceSession
    @ObservationIgnored private var pill: OverlayPillPanel?
    @ObservationIgnored private var conversation: ConversationPanelWindow?

    private(set) var isConversationVisible = false

    init(session: VoiceSession) {
        self.session = session
    }

    func showPill() {
        if pill == nil { pill = OverlayPillPanel(session: session) }
        pill?.orderFrontRegardless()
    }

    func hidePill() {
        pill?.orderOut(nil)
    }

    func toggleConversation() {
        if isConversationVisible {
            conversation?.orderOut(nil)
            isConversationVisible = false
        } else {
            if conversation == nil {
                conversation = ConversationPanelWindow(session: session) { [weak self] in
                    self?.isConversationVisible = false
                }
            }
            conversation?.present()
            isConversationVisible = true
        }
    }
}

// MARK: - Menu bar

private struct MenuBarLabel: View {
    let session: VoiceSession

    var body: some View {
        Image(systemName: session.state.symbol)
            .symbolEffect(.variableColor.iterative, isActive: session.state == .listening)
            .accessibilityLabel("Voice Agent: \(session.state.label)")
    }
}

/// Glass dropdown from the menu bar icon.
struct MenuBarContent: View {
    @Environment(VoiceSession.self) private var session
    @Environment(PanelCoordinator.self) private var panels
    @Environment(\.openSettings) private var openSettings
    @Namespace private var glass

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !session.transcript.isEmpty {
                Text(session.transcript)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            GlassEffectContainer(spacing: 10) {
                VStack(spacing: 8) {
                    Button {
                        session.toggle()
                    } label: {
                        Label(
                            session.state.isBusy ? "Stop" : "Start Listening",
                            systemImage: session.state.isBusy ? "stop.fill" : "mic.fill"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.space, modifiers: .option)
                    .glassEffectID("primary", in: glass)

                    HStack(spacing: 8) {
                        Button {
                            panels.toggleConversation()
                        } label: {
                            Label("Conversation", systemImage: "bubble.left.and.text.bubble.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .tint(.clear)
                        .glassEffectID("conversation", in: glass)

                        Button {
                            NSApp.activate()
                            openSettings()
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                        .tint(.clear)
                        .glassEffectID("settings", in: glass)
                    }
                }
                .controlSize(.large)
            }

            if !session.permissions.allGranted {
                permissionsHint
            }

            Divider()

            HStack {
                if let latency = session.lastJevLatency {
                    Text("Jev \(latency.formatted(.units(allowed: [.milliseconds])))")
                        .monospacedDigit()
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .keyboardShortcut("q")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(width: 300)
        .animation(.smooth, value: session.state)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: session.state.symbol)
                .font(.title3)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 36, height: 36)
                .glassEffect(session.state.glass, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text("Voice Agent").font(.headline)
                Text(session.state.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text("⌥Space")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
        }
    }

    private var permissionsHint: some View {
        Label("Some permissions are missing — open Settings to grant them.", systemImage: "lock.shield")
            .font(.caption)
            .foregroundStyle(.orange)
    }
}
