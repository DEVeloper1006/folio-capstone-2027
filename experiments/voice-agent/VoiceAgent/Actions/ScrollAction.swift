import CoreGraphics

/// Scrolls with a synthesized wheel event, positioned over the target element when one is given.
@MainActor
struct ScrollAction: MacAction {
    var lines: Int32 = 6

    func execute(_ request: ActionRequest, in context: ActionContext) async throws -> ActionResult {
        let delta: Int32 = request.kind == .scrollUp ? lines : -lines

        var location: CGPoint?
        if let index = request.targetIndex {
            guard let element = context.table.entry(at: index) else { throw ActionError.unknownElement(index) }
            location = element.center
        }

        guard let event = CGEvent(
            scrollWheelEvent2Source: CGEventSource(stateID: .hidSystemState),
            units: .line,
            wheelCount: 1,
            wheel1: delta,
            wheel2: 0,
            wheel3: 0
        ) else { throw ActionError.eventCreationFailed }

        if let location { event.location = location }
        event.post(tap: .cghidEventTap)
        return .ok(request.kind == .scrollUp ? "Scrolled up" : "Scrolled down")
    }
}
