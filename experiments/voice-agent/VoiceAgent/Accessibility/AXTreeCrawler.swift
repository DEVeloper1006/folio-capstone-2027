import AppKit
import ApplicationServices

/// Walks the focused application's accessibility tree and collects actionable elements.
///
/// Runs on the main actor: `AXUIElement` is not `Sendable`, and every call is bounded by
/// a short messaging timeout so an unresponsive app can't stall the UI for long.
@MainActor
struct AXTreeCrawler {
    var maxElements = 50
    var maxDepth = 25
    var maxVisited = 3_000
    var messagingTimeout: Float = 0.25

    /// Roles that are targets in their own right.
    static let actionableRoles: Set<String> = [
        kAXButtonRole, kAXTextFieldRole, "AXLink", kAXMenuItemRole, kAXCheckBoxRole,
        kAXRadioButtonRole, kAXPopUpButtonRole, kAXSliderRole,
        // Text inputs beyond AXTextField, so TYPE_TEXT has somewhere to type.
        kAXTextAreaRole, kAXComboBoxRole, "AXSearchField",
    ]

    /// Anything else (AXStaticText, AXGroup, AXImage, AXCell…) only counts if it can be pressed.
    /// Web and Electron UIs expose most clickable controls as AXGroup/AXStaticText with AXPress.
    static let pressActions: Set<String> = [kAXPressAction, kAXConfirmAction]

    /// Containers whose children are worth descending into but that are not targets themselves.
    static let skipRoles: Set<String> = [kAXMenuBarRole, kAXMenuBarItemRole]

    enum CrawlError: Error, CustomStringConvertible {
        case notTrusted
        case noFocusedApp
        case noWindow(app: String)

        var description: String {
            switch self {
            case .notTrusted: "Accessibility permission not granted"
            case .noFocusedApp: "No focused application"
            case .noWindow(let app): "\(app) has no focused window"
            }
        }
    }

    func crawlFocusedApp() throws -> ElementTable {
        guard AXIsProcessTrusted() else { throw CrawlError.notTrusted }

        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)

        guard let app: AXUIElement = systemWide.attribute(kAXFocusedApplicationAttribute) else {
            throw CrawlError.noFocusedApp
        }
        AXUIElementSetMessagingTimeout(app, messagingTimeout)
        let appName: String = app.attribute(kAXTitleAttribute) ?? frontmostName() ?? "Unknown"

        let window: AXUIElement? = app.attribute(kAXFocusedWindowAttribute)
            ?? app.attribute(kAXMainWindowAttribute)
        guard let window else { throw CrawlError.noWindow(app: appName) }

        let windowTitle: String? = window.attribute(kAXTitleAttribute)
        let elements = collect(from: window)
        return ElementTable(appName: appName, windowTitle: windowTitle, elements: elements)
    }

    /// Walks the tree via `kAXChildrenAttribute` (preferring visible children when the app exposes them).
    /// Breadth-first so top-level controls (toolbars, primary buttons) win the 50-slot budget
    /// over deeply nested list cells.
    private func collect(from root: AXUIElement) -> [ElementEntry] {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var head = 0
        var found: [ElementEntry] = []

        while head < queue.count, found.count < maxElements, head < maxVisited {
            let (element, depth) = queue[head]
            head += 1

            if let observed = observe(element, index: found.count) {
                found.append(observed)
            }

            guard depth < maxDepth else { continue }
            let children: [AXUIElement] = element.attribute(kAXVisibleChildrenAttribute)
                ?? element.attribute(kAXChildrenAttribute)
                ?? []
            queue.append(contentsOf: children.map { ($0, depth + 1) })
        }
        return found
    }

    private func observe(_ element: AXUIElement, index: Int) -> ElementEntry? {
        guard let role: String = element.attribute(kAXRoleAttribute),
              !Self.skipRoles.contains(role) else { return nil }

        let actions = element.actionNames()
        let isActionable = Self.actionableRoles.contains(role)
            || !Self.pressActions.isDisjoint(with: actions)
        guard isActionable else { return nil }

        if let enabled: Bool = element.attribute(kAXEnabledAttribute), !enabled { return nil }

        let frame = element.frame()
        guard frame.width > 1, frame.height > 1 else { return nil }

        return ElementEntry(
            index: index,
            ref: element,
            role: role,
            subrole: element.attribute(kAXSubroleAttribute),
            title: element.attribute(kAXTitleAttribute) ?? element.attribute(kAXDescriptionAttribute),
            identifier: element.attribute(kAXIdentifierAttribute),
            value: element.stringValue(),
            help: element.attribute(kAXHelpAttribute) ?? element.attribute(kAXPlaceholderValueAttribute),
            actions: actions,
            frame: frame
        )
    }

    private func frontmostName() -> String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }
}

// MARK: - AXUIElement helpers

extension AXUIElement {
    func attribute<T>(_ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success,
              let value else { return nil }
        // AXUIElement / AXValue are CF types; conditional casts from CFTypeRef always succeed
        // for CF types, so check the CF type id explicitly.
        if T.self == AXUIElement.self {
            guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
            return (value as! T)
        }
        return value as? T
    }

    func stringValue() -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, kAXValueAttribute as CFString, &value) == .success,
              let value else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    func actionNames() -> [String] {
        var names: CFArray?
        guard AXUIElementCopyActionNames(self, &names) == .success,
              let names = names as? [String] else { return [] }
        return names
    }

    func frame() -> CGRect {
        var origin = CGPoint.zero
        var size = CGSize.zero
        if let value = axValue(kAXPositionAttribute) {
            AXValueGetValue(value, .cgPoint, &origin)
        }
        if let value = axValue(kAXSizeAttribute) {
            AXValueGetValue(value, .cgSize, &size)
        }
        return CGRect(origin: origin, size: size)
    }

    private func axValue(_ name: String) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}
