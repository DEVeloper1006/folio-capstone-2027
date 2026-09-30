import ApplicationServices
import CoreGraphics

/// Presses an observed element. Prefers the semantic AX action; falls back to a synthesized
/// mouse click at the element's center (still derived from the observed frame, never from the model).
@MainActor
struct ClickAction: MacAction {
    func execute(_ request: ActionRequest, in context: ActionContext) async throws -> ActionResult {
        guard let index = request.targetIndex else { throw ActionError.missingArgument("target") }
        guard let element = context.table.entry(at: index) else { throw ActionError.unknownElement(index) }

        for action in [kAXPressAction, kAXConfirmAction, kAXPickAction] where element.actions.contains(action) {
            if AXUIElementPerformAction(element.ref, action as CFString) == .success {
                return .ok("Pressed \(element.summary)")
            }
        }

        try postClick(at: element.center)
        return .ok("Clicked \(element.summary)")
    }

    private func postClick(at point: CGPoint) throws {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        else { throw ActionError.eventCreationFailed }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }
}
