import ApplicationServices
import Foundation

/// A single observed, actionable UI element.
///
/// `ref` is the live `AXUIElement`; the model only ever sees `id` plus a text description.
struct ObservedElement: Identifiable {
    let id: String            // "e0" … "e49"
    let ref: AXUIElement
    let role: String
    let subrole: String?
    let title: String?
    let value: String?
    let help: String?
    let frame: CGRect
    let actions: [String]

    var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

    var isTextInput: Bool {
        [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField"].contains(role)
            || subrole == "AXSearchField"
    }

    var isScrollable: Bool { role == kAXScrollAreaRole }

    /// Short human-readable label used as a Jev choice criterion.
    var summary: String {
        let kind = role.replacingOccurrences(of: "AX", with: "").lowercased()
        let label = [title, help, value]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
            .map { "'\(String($0.prefix(60)))'" } ?? "(unlabeled)"
        return "\(kind) \(label)"
    }
}

/// Indexed, capped list of actionable elements for one observation of the screen.
///
/// Rebuilt on every agent step; ids are only valid for the table that issued them.
struct ElementTable {
    let appName: String
    let windowTitle: String?
    let elements: [ObservedElement]

    static var empty: ElementTable { ElementTable(appName: "", windowTitle: nil, elements: []) }

    var isEmpty: Bool { elements.isEmpty }

    subscript(id: String) -> ObservedElement? {
        elements.first { $0.id == id }
    }

    /// Jev `choice` criteria: `["e3": "button 'Send'", ...]`.
    func criteria() -> [String: String] {
        Dictionary(uniqueKeysWithValues: elements.map { ($0.id, $0.summary) })
    }

    /// Criteria restricted to elements that can accept typed text.
    func textInputCriteria() -> [String: String] {
        Dictionary(uniqueKeysWithValues: elements.filter(\.isTextInput).map { ($0.id, $0.summary) })
    }

    /// Plain-text rendering for the Jev `state` string and debug logs.
    func render() -> String {
        var lines = ["App: \(appName)" + (windowTitle.map { " — window: \($0)" } ?? "")]
        lines += elements.map { "[\($0.id)] \($0.summary)" }
        return lines.joined(separator: "\n")
    }
}
