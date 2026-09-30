import ApplicationServices
import CoreGraphics

/// Types text into an observed text element.
///
/// Strategy: focus the element, insert at the caret via `kAXSelectedTextAttribute`
/// (non-destructive), else fall back to synthesized unicode keystrokes.
@MainActor
struct TypeTextAction: MacAction {
    func execute(_ request: ActionRequest, in context: ActionContext) async throws -> ActionResult {
        guard let text = request.text, !text.isEmpty else { throw ActionError.missingArgument("text") }

        if let index = request.targetIndex {
            guard let element = context.table.entry(at: index) else { throw ActionError.unknownElement(index) }
            AXUIElementSetAttributeValue(element.ref, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            try await Task.sleep(for: .milliseconds(80))

            if AXUIElementSetAttributeValue(element.ref, kAXSelectedTextAttribute as CFString, text as CFString) == .success {
                return .ok("Typed into \(element.summary)")
            }
        }

        try postUnicode(text)
        return .ok("Typed \(text.count) characters")
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
