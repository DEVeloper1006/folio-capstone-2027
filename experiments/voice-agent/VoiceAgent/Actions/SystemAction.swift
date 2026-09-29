import Foundation

/// System-level toggles. Volume goes through fixed AppleScript templates.
///
/// Brightness and Do Not Disturb have no public API on macOS 26; they are stubbed rather than
/// driven through private frameworks. A Shortcuts-based route ("Set Focus") is the likely path.
@MainActor
struct SystemAction: MacAction {
    var volumeStep = 10

    func execute(_ request: ActionRequest, in context: ActionContext) async throws -> ActionResult {
        switch request.kind {
        case .volumeUp:
            try AppleScriptBridge.run(.volumeUp(step: volumeStep))
            return .ok("Volume up")
        case .volumeDown:
            try AppleScriptBridge.run(.volumeDown(step: volumeStep))
            return .ok("Volume down")
        case .toggleMute:
            try AppleScriptBridge.run(.toggleMute)
            return .ok("Toggled mute")
        case .toggleDoNotDisturb:
            // TODO: run a user-installed Shortcut ("Toggle Focus") via `shortcuts run`, with a fixed name.
            throw ActionError.unsupported("Do Not Disturb has no public API yet")
        default:
            throw ActionError.unsupported(request.kind.rawValue)
        }
    }
}
