import Foundation

/// Runs a fixed set of code-owned AppleScript templates.
///
/// Scripts are never assembled from model output. Each case is a static source string;
/// the only parameters are typed Swift values produced by code (e.g. a clamped Int).
@MainActor
enum AppleScriptBridge {
    enum Script {
        case volumeUp(step: Int)
        case volumeDown(step: Int)
        case setMuted(Bool)
        case toggleMute

        var source: String {
            switch self {
            case .volumeUp(let step):
                let step = max(1, min(step, 50))
                return "set volume output volume ((output volume of (get volume settings)) + \(step))"
            case .volumeDown(let step):
                let step = max(1, min(step, 50))
                return "set volume output volume ((output volume of (get volume settings)) - \(step))"
            case .setMuted(let muted):
                return "set volume output muted \(muted ? "true" : "false")"
            case .toggleMute:
                return "set volume output muted (not (output muted of (get volume settings)))"
            }
        }
    }

    struct ScriptError: Error, CustomStringConvertible {
        let description: String
    }

    @discardableResult
    static func run(_ script: Script) throws -> String? {
        guard let appleScript = NSAppleScript(source: script.source) else {
            throw ScriptError(description: "Failed to compile script")
        }
        var errorInfo: NSDictionary?
        let result = appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo {
            throw ScriptError(description: errorInfo[NSAppleScript.errorMessage] as? String ?? "AppleScript error")
        }
        return result.stringValue
    }
}
