import AppKit
import ApplicationServices

/// System-level controls.
///
/// - Volume, mute, brightness: synthesized media-key events (the same `NX_SYSDEFINED` events the
///   keyboard's F-keys send), so the system HUD appears. Posting them needs Accessibility; without it,
///   volume and mute fall back to fixed AppleScript templates.
/// - Do Not Disturb: macOS has no public API to set Focus, so this runs a user-created Shortcut with
///   a fixed name. The name is a constant, never model input.
@MainActor
struct SystemAction: MacAction {
    var volumeStep = 10

    static let focusShortcutName = "Toggle Focus"

    /// `NX_KEYTYPE_*` values from IOKit's `ev_keymap.h`.
    enum MediaKey: Int32 {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
    }

    func execute(_ request: ActionRequest, in context: ActionContext) async throws -> ActionResult {
        switch request.kind {
        case .volumeUp:
            try press(.soundUp, fallback: .volumeUp(step: volumeStep))
            return .ok("Volume up")
        case .volumeDown:
            try press(.soundDown, fallback: .volumeDown(step: volumeStep))
            return .ok("Volume down")
        case .toggleMute:
            try press(.mute, fallback: .toggleMute)
            return .ok("Toggled mute")
        case .brightnessUp:
            guard AXIsProcessTrusted() else { return .failed(VoiceSession.accessibilityMessage) }
            try postMediaKey(.brightnessUp)
            return .ok("Brightness up")
        case .brightnessDown:
            guard AXIsProcessTrusted() else { return .failed(VoiceSession.accessibilityMessage) }
            try postMediaKey(.brightnessDown)
            return .ok("Brightness down")
        case .toggleDoNotDisturb:
            return try await runFocusShortcut()
        default:
            throw ActionError.unsupported(request.kind.rawValue)
        }
    }

    private func press(_ key: MediaKey, fallback: AppleScriptBridge.Script) throws {
        if AXIsProcessTrusted() {
            try postMediaKey(key)
        } else {
            try AppleScriptBridge.run(fallback)
        }
    }

    /// Key down + key up as `NSEvent.systemDefined` subtype 8 (aux control buttons).
    private func postMediaKey(_ key: MediaKey) throws {
        for (flags, state) in [(0xA00, 0xA), (0xB00, 0xB)] {
            guard let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: Int((key.rawValue << 16) | Int32(state << 8)),
                data2: -1
            ), let cgEvent = event.cgEvent else { throw ActionError.eventCreationFailed }
            cgEvent.post(tap: .cghidEventTap)
        }
    }

    private func runFocusShortcut() async throws -> ActionResult {
        let status = try await Self.runShortcuts(["run", Self.focusShortcutName])
        return status == 0
            ? .ok("Toggled Focus")
            : .failed("Create a Shortcut named \(Self.focusShortcutName) to control Focus")
    }

    /// Runs `/usr/bin/shortcuts` off the main thread and returns its exit status.
    private static func runShortcuts(_ arguments: [String]) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts")
            process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
