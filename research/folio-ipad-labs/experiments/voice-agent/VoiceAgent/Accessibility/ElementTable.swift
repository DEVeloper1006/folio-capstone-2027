import ApplicationServices
import Foundation

/// A single observed, actionable UI element.
///
/// `ref` is the live `AXUIElement`; the model only ever sees `index` plus a text description,
/// and picks an index back. Actions resolve the index to `ref` through the table that issued it.
struct ElementEntry: Identifiable {
    let index: Int            // 0 … 79
    let ref: AXUIElement
    let role: String
    let subrole: String?
    let title: String?
    let identifier: String?   // kAXIdentifierAttribute (developer-assigned, often stable)
    let value: String?
    let help: String?
    let actions: [String]
    let frame: CGRect

    var id: Int { index }

    /// Same element at a new position (indices are assigned after the native and web passes merge).
    func reindexed(_ newIndex: Int) -> ElementEntry {
        ElementEntry(
            index: newIndex, ref: ref, role: role, subrole: subrole, title: title, identifier: identifier,
            value: value, help: help, actions: actions, frame: frame
        )
    }

    var center: CGPoint { CGPoint(x: frame.midX, y: frame.midY) }

    var isTextInput: Bool {
        [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole, "AXSearchField"].contains(role)
            || subrole == "AXSearchField"
    }

    /// Short human-readable label used as a Jev choice criterion. Text inputs also say whether they're
    /// empty, so Jev can tell "click the field, then type" from "already typed".
    var summary: String {
        let kind = role.replacingOccurrences(of: "AX", with: "").lowercased()
        var text = "\(kind) \(fieldLabel.map { "'\($0)'" } ?? "(unlabeled)")"
        if isTextInput {
            let current = value.map(Self.oneLine) ?? ""
            text += current.isEmpty ? " (empty)" : " (value: '\(current.prefix(40))')"
        }
        return text
    }

    /// Label that ignores the value for text inputs (the value is reported separately).
    private var fieldLabel: String? {
        isTextInput ? [title, help].compactMap { $0.map(Self.oneLine) }.first { !$0.isEmpty }.map { String($0.prefix(60)) } : label
    }

    /// One line of the Jev state table: `[3] AXButton "Send" id=send-btn actions=AXPress`.
    var serialized: String {
        let label = self.label
        var parts: [String] = ["[\(index)]", role]
        if let label {
            parts.append("\"\(label)\"")
        }
        if let identifier, !identifier.isEmpty {
            parts.append("id=\(identifier.prefix(40))")
        }
        // Current contents of text inputs help Jev tell "empty field" from "already typed".
        if isTextInput, let value = value.map(Self.oneLine), !value.isEmpty, value != label {
            parts.append("value=\"\(value.prefix(40))\"")
        }
        // Only standard AX actions: apps also expose custom actions as multi-line descriptors
        // ("Name:Move previous\nTarget:0x0…") that would break the one-line-per-element table.
        let standard = actions.filter { $0.hasPrefix("AX") }
        if !standard.isEmpty {
            parts.append("actions=" + standard.joined(separator: ","))
        }
        return parts.joined(separator: " ")
    }

    /// Name for spoken confirmations: "Submit", or "the button" when unlabeled.
    var spokenName: String {
        label ?? "the " + role.replacingOccurrences(of: "AX", with: "").lowercased()
    }

    /// First non-empty of title / help / value, on one line (web labels often contain newlines).
    var label: String? {
        [title, help, value]
            .compactMap { $0.map(Self.oneLine) }
            .first { !$0.isEmpty }
            .map { String($0.prefix(60)) }
    }

    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// Indexed, capped list of actionable elements for one observation of the screen.
///
/// Rebuilt on every agent step; indices are only valid for the table that issued them.
struct ElementTable {
    let appName: String
    let windowTitle: String?
    let elements: [ElementEntry]

    static var empty: ElementTable { ElementTable(appName: "", windowTitle: nil, elements: []) }

    var isEmpty: Bool { elements.isEmpty }

    /// Entries are stored in index order, so an index is a direct position.
    func entry(at index: Int) -> ElementEntry? {
        elements.indices.contains(index) ? elements[index] : nil
    }

    /// Jev option key (`"7"`) → entry.
    func entry(forKey key: String?) -> ElementEntry? {
        key.flatMap(Int.init).flatMap(entry(at:))
    }

    /// The live element to act on.
    func element(at index: Int) -> AXUIElement? {
        entry(at: index)?.ref
    }

    /// Jev `choice` criteria for `target_index`: `["0": "button 'Send'", ...]`.
    func targetCriteria() -> [String: String] {
        Dictionary(uniqueKeysWithValues: elements.map { (String($0.index), $0.summary) })
    }

    /// Criteria restricted to elements that can accept typed text.
    func textInputCriteria() -> [String: String] {
        Dictionary(uniqueKeysWithValues: elements.filter(\.isTextInput).map { (String($0.index), $0.summary) })
    }

    /// Structured text for the Jev `state` field and debug logs.
    func serialize() -> String {
        guard !appName.isEmpty else { return "Screen: (nothing observable)" }
        var lines = ["App: \(appName)" + (windowTitle.map { " — window: \($0)" } ?? "")]
        if elements.isEmpty {
            lines.append("(no actionable elements)")
        } else {
            lines.append("Elements (index role \"label\" id actions):")
            lines += elements.map(\.serialized)
        }
        return lines.joined(separator: "\n")
    }
}
