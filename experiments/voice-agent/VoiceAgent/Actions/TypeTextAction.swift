import ApplicationServices
import CoreGraphics

/// Types text into an observed text element.
///
/// Strategy: focus the element, insert at the caret via `kAXSelectedTextAttribute` (non-destructive),
/// then read `kAXValueAttribute` back. Web and Electron fields often accept the AX write without
/// changing, so an unchanged value falls back to synthesized unicode keystrokes into the focused field.
@MainActor
struct TypeTextAction: MacAction {
    var focusDelay: Duration = .milliseconds(120)

    func execute(_ request: ActionRequest, in context: ActionContext) async throws -> ActionResult {
        guard let text = request.text, !text.isEmpty else { throw ActionError.missingArgument("text") }

        if let index = request.targetIndex {
            guard let element = context.table.entry(at: index) else { throw ActionError.unknownElement(index) }
            AXUIElementSetAttributeValue(element.ref, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            try await Task.sleep(for: focusDelay)

            let before = element.ref.stringValue()
            if AXUIElementSetAttributeValue(element.ref, kAXSelectedTextAttribute as CFString, text as CFString) == .success {
                let after = element.ref.stringValue()
                if after != before, after?.contains(text) ?? false {
                    DebugLog.print("Type", "AX insert verified in \(element.role) '\(element.spokenName)'")
                    return .ok("Typing \(text.prefix(60))")
                }
                DebugLog.print("Type", "AX insert reported success but value unchanged; falling back to key events")
            }
        }

        try postUnicode(text)
        return .ok("Typing \(text.prefix(60))")
    }

    /// CGEvent carries at most ~20 UTF-16 units per event, so send in chunks.
    private func postUnicode(_ text: String) throws {
        let source = CGEventSource(stateID: .hidSystemState)
        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            let chunk = Array(units[index..<min(index + 20, units.count)])
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else { throw ActionError.eventCreationFailed }
            chunk.withUnsafeBufferPointer { buffer in
                down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
            }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            index += 20
        }
    }
}
