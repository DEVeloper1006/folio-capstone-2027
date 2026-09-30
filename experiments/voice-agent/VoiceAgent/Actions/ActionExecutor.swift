import AppKit
import Foundation

// MARK: - Registry

/// The closed set of things the agent can do. Jev only ever returns one of these raw values;
/// anything else is rejected by `ActionKind(rawValue:)`.
enum ActionKind: String, CaseIterable, Sendable {
    // Computer-use verbs (task loop)
    case openApp = "OPEN_APP"
    case click = "CLICK"
    case typeText = "TYPE_TEXT"
    case pressKey = "PRESS_KEY"
    case scrollUp = "SCROLL_UP"
    case scrollDown = "SCROLL_DOWN"
    case wait = "WAIT"
    case done = "DONE"
    case blocked = "BLOCKED"
    // System actions (single-shot only)
    case volumeUp = "VOLUME_UP"
    case volumeDown = "VOLUME_DOWN"
    case toggleMute = "TOGGLE_MUTE"
    case toggleDoNotDisturb = "TOGGLE_DND"

    /// Criteria text shown to Jev for this option.
    var criterion: String {
        switch self {
        case .openApp: "Launch or switch to an application"
        case .click: "Click/press a specific on-screen control"
        case .typeText: "Type text into a text field"
        case .pressKey: "Press a keyboard key or shortcut"
        case .scrollUp: "Scroll the content up"
        case .scrollDown: "Scroll the content down"
        case .wait: "Wait briefly for the screen to update"
        case .done: "The goal is already achieved"
        case .blocked: "The goal cannot be achieved from here (missing element, needs user input, unsafe)"
        case .volumeUp: "Turn the system volume up"
        case .volumeDown: "Turn the system volume down"
        case .toggleMute: "Mute or unmute system audio"
        case .toggleDoNotDisturb: "Turn Do Not Disturb / Focus on or off"
        }
    }

    /// SF Symbol for the pill while this verb executes.
    var symbol: String {
        switch self {
        case .openApp: "macwindow.badge.plus"
        case .click: "cursorarrow.click.2"
        case .typeText: "keyboard"
        case .pressKey: "command"
        case .scrollUp: "arrow.up.circle"
        case .scrollDown: "arrow.down.circle"
        case .wait: "hourglass"
        case .done: "checkmark"
        case .blocked: "hand.raised.fill"
        case .volumeUp: "speaker.plus.fill"
        case .volumeDown: "speaker.minus.fill"
        case .toggleMute: "speaker.slash.fill"
        case .toggleDoNotDisturb: "moon.fill"
        }
    }

    /// Verbs available inside the multi-step task loop.
    static let taskVerbs: [ActionKind] = [
        .openApp, .click, .typeText, .pressKey, .scrollUp, .scrollDown, .wait, .done, .blocked,
    ]

    /// Actions a single utterance can trigger directly without grounding against the screen.
    static let singleShot: [ActionKind] = [
        .openApp, .pressKey, .scrollUp, .scrollDown,
        .volumeUp, .volumeDown, .toggleMute, .toggleDoNotDisturb,
    ]

    /// Actions that need an observed element and therefore go through the task loop.
    var needsElement: Bool { self == .click || self == .typeText }

    var isTerminal: Bool { self == .done || self == .blocked }

    static func criteria(_ kinds: [ActionKind]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: kinds.map { ($0.rawValue, $0.criterion) })
    }
}

/// A key press resolved from the `KeyChord` registry: a virtual key code plus modifier flags.
struct KeyPress: Sendable, Equatable {
    let keyCode: CGKeyCode
    let modifiers: CGEventFlags
    let name: String
}

/// A fully-resolved action: every argument is either a registry key or an observed element.
struct ActionRequest: Sendable, CustomStringConvertible {
    var kind: ActionKind
    var targetIndex: Int? = nil      // ElementTable index, e.g. 7
    var appName: String? = nil       // AppCatalog key
    var key: KeyPress? = nil         // from the KeyChord registry
    var text: String? = nil          // TYPE_TEXT payload: a verbatim span of the user's words

    var description: String {
        var parts = [kind.rawValue]
        if let targetIndex { parts.append("#\(targetIndex)") }
        if let appName { parts.append(appName) }
        if let key { parts.append(key.name) }
        if let text { parts.append("\"\(text.prefix(40))\"") }
        return parts.joined(separator: " ")
    }
}

struct ActionResult: Sendable {
    var success: Bool
    var message: String

    static func ok(_ message: String) -> ActionResult { .init(success: true, message: message) }
    static func failed(_ message: String) -> ActionResult { .init(success: false, message: message) }
}

enum ActionError: Error, CustomStringConvertible {
    case missingArgument(String)
    case unknownElement(Int)
    case unsupported(String)
    case eventCreationFailed
    case axFailure(String, AXError)

    var description: String {
        switch self {
        case .missingArgument(let arg): "Missing argument: \(arg)"
        case .unknownElement(let index): "Element #\(index) is not in the current element table"
        case .unsupported(let what): "Unsupported: \(what)"
        case .eventCreationFailed: "Could not create input event"
        case .axFailure(let op, let code): "\(op) failed (AXError \(code.rawValue))"
        }
    }
}

/// Everything an action handler may touch. Handlers never see raw model output.
struct ActionContext {
    var table: ElementTable
    var apps: AppCatalog
}

@MainActor
protocol MacAction {
    func execute(_ request: ActionRequest, in context: ActionContext) async throws -> ActionResult
}

// MARK: - Executor

@MainActor
final class ActionExecutor {
    let apps: AppCatalog

    private let openApp = OpenAppAction()
    private let click = ClickAction()
    private let typeText = TypeTextAction()
    private let pressKey = PressKeyAction()
    private let scroll = ScrollAction()
    private let system = SystemAction()

    init(apps: AppCatalog) {
        self.apps = apps
    }

    func execute(_ request: ActionRequest, table: ElementTable = .empty) async throws -> ActionResult {
        let context = ActionContext(table: table, apps: apps)
        switch request.kind {
        case .openApp:
            return try await openApp.execute(request, in: context)
        case .click:
            return try await click.execute(request, in: context)
        case .typeText:
            return try await typeText.execute(request, in: context)
        case .pressKey:
            return try await pressKey.execute(request, in: context)
        case .scrollUp, .scrollDown:
            return try await scroll.execute(request, in: context)
        case .volumeUp, .volumeDown, .toggleMute, .toggleDoNotDisturb:
            return try await system.execute(request, in: context)
        case .wait:
            try await Task.sleep(for: .milliseconds(800))
            return .ok("Waited")
        case .done:
            return .ok("Done")
        case .blocked:
            return .failed("Blocked")
        }
    }
}
