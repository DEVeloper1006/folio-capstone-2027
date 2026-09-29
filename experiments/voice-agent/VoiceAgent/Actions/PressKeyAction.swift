import Carbon.HIToolbox
import CoreGraphics

/// Static registry of keys and shortcuts the model may choose from.
enum KeyChord: String, CaseIterable, Sendable {
    case returnKey = "RETURN"
    case escape = "ESCAPE"
    case tab = "TAB"
    case delete = "DELETE"
    case space = "SPACE"
    case up = "UP"
    case down = "DOWN"
    case left = "LEFT"
    case right = "RIGHT"
    case copy = "CMD_C"
    case paste = "CMD_V"
    case selectAll = "CMD_A"
    case undo = "CMD_Z"
    case newItem = "CMD_N"
    case newTab = "CMD_T"
    case closeWindow = "CMD_W"
    case find = "CMD_F"
    case save = "CMD_S"
    case focusAddressBar = "CMD_L"
    case spotlight = "CMD_SPACE"

    var keyCode: CGKeyCode {
        let code: Int = switch self {
        case .returnKey: kVK_Return
        case .escape: kVK_Escape
        case .tab: kVK_Tab
        case .delete: kVK_Delete
        case .space, .spotlight: kVK_Space
        case .up: kVK_UpArrow
        case .down: kVK_DownArrow
        case .left: kVK_LeftArrow
        case .right: kVK_RightArrow
        case .copy: kVK_ANSI_C
        case .paste: kVK_ANSI_V
        case .selectAll: kVK_ANSI_A
        case .undo: kVK_ANSI_Z
        case .newItem: kVK_ANSI_N
        case .newTab: kVK_ANSI_T
        case .closeWindow: kVK_ANSI_W
        case .find: kVK_ANSI_F
        case .save: kVK_ANSI_S
        case .focusAddressBar: kVK_ANSI_L
        }
        return CGKeyCode(code)
    }

    var flags: CGEventFlags {
        rawValue.hasPrefix("CMD_") ? .maskCommand : []
    }

    var criterion: String {
        switch self {
        case .returnKey: "Return / Enter: submit or confirm"
        case .escape: "Escape: cancel or dismiss"
        case .tab: "Tab: move to next field"
        case .delete: "Delete / Backspace"
        case .space: "Space bar"
        case .up: "Up arrow"
        case .down: "Down arrow"
        case .left: "Left arrow"
        case .right: "Right arrow"
        case .copy: "Cmd+C copy"
        case .paste: "Cmd+V paste"
        case .selectAll: "Cmd+A select all"
        case .undo: "Cmd+Z undo"
        case .newItem: "Cmd+N new window/document/message"
        case .newTab: "Cmd+T new tab"
        case .closeWindow: "Cmd+W close window or tab"
        case .find: "Cmd+F find"
        case .save: "Cmd+S save"
        case .focusAddressBar: "Cmd+L focus browser address bar"
        case .spotlight: "Cmd+Space open Spotlight"
        }
    }

    static func criteria() -> [String: String] {
        Dictionary(uniqueKeysWithValues: allCases.map { ($0.rawValue, $0.criterion) })
    }
}

@MainActor
struct PressKeyAction: MacAction {
    func execute(_ request: ActionRequest, in context: ActionContext) async throws -> ActionResult {
        guard let chord = request.key else { throw ActionError.missingArgument("key") }
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: chord.keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: chord.keyCode, keyDown: false)
        else { throw ActionError.eventCreationFailed }
        down.flags = chord.flags
        up.flags = chord.flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return .ok("Pressed \(chord.rawValue)")
    }
}
