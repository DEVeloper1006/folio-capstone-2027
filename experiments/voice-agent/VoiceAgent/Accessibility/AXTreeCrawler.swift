import AppKit
import ApplicationServices

/// Walks the focused application's accessibility tree and collects actionable elements.
///
/// Runs on the main actor: `AXUIElement` is not `Sendable`, and every call is bounded by
/// a short messaging timeout so an unresponsive app can't stall the UI for long.
@MainActor
struct AXTreeCrawler {
    /// Total elements sent to Jev. Browsers and IDEs have deep trees; 50 missed important controls.
    var maxElements = 80
    /// Slots reserved for page content inside `AXWebArea`s, so browser chrome can't starve them.
    var maxWebElements = 50
    var maxDepth = 25
    var maxWebDepth = 45
    var maxVisited = 3_000
    var maxWebVisited = 5_000
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

    static let webAreaRole = "AXWebArea"

    /// Chromium browsers only build their web accessibility tree when an assistive client asks for it.
    static let chromiumBundleIDs: Set<String> = [
        "com.google.Chrome", "company.thebrowser.Browser", "com.brave.Browser",
        "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]

    /// Apps already switched into full accessibility mode (per pid, for the app's lifetime).
    private static var enabledPIDs: Set<pid_t> = []

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

    /// Sleeps `delay` (to let the UI settle after an action), then crawls. With `pid`, crawls that
    /// app, which is used after an app switch because the system-wide focused app can lag behind.
    func crawl(delay: Duration = .zero, pid: pid_t? = nil) async throws -> ElementTable {
        if delay > .zero { try await Task.sleep(for: delay) }
        return try crawlApp(pid: pid)
    }

    func crawlFocusedApp() throws -> ElementTable {
        try crawlApp(pid: nil)
    }

    private func crawlApp(pid: pid_t?) throws -> ElementTable {
        guard AXIsProcessTrusted() else { throw CrawlError.notTrusted }

        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)

        let app: AXUIElement
        if let pid {
            app = AXUIElementCreateApplication(pid)
        } else {
            guard let focused: AXUIElement = systemWide.attribute(kAXFocusedApplicationAttribute) else {
                throw CrawlError.noFocusedApp
            }
            app = focused
        }
        AXUIElementSetMessagingTimeout(app, messagingTimeout)

        var appPID: pid_t = 0
        AXUIElementGetPid(app, &appPID)
        let running = NSRunningApplication(processIdentifier: appPID)
        enableWebAccessibility(app, pid: appPID, bundleID: running?.bundleIdentifier)

        let appName: String = app.attribute(kAXTitleAttribute) ?? running?.localizedName ?? "Unknown"
        let window: AXUIElement? = app.attribute(kAXFocusedWindowAttribute)
            ?? app.attribute(kAXMainWindowAttribute)
        guard let window else { throw CrawlError.noWindow(app: appName) }

        let windowTitle: String? = window.attribute(kAXTitleAttribute)
        let elements = collect(from: window)
        return ElementTable(appName: appName, windowTitle: windowTitle, elements: elements)
    }

    /// Chromium and Electron expose web content to AX only on request: `AXManualAccessibility` (Electron,
    /// harmless elsewhere) and `AXEnhancedUserInterface` (Chromium browsers). Set once per process.
    private func enableWebAccessibility(_ app: AXUIElement, pid: pid_t, bundleID: String?) {
        guard pid > 0, !Self.enabledPIDs.contains(pid) else { return }
        Self.enabledPIDs.insert(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if let bundleID, Self.chromiumBundleIDs.contains(bundleID) {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }

    /// Two passes over the window:
    /// 1. Breadth-first over the native UI (preferring visible children), so toolbars and primary
    ///    buttons win the budget over nested list cells. `AXWebArea`s are set aside, not descended.
    /// 2. Breadth-first inside each web area via `kAXChildrenAttribute` (visible-children is often
    ///    empty there), deeper, keeping only elements inside the window. Up to `maxWebElements`.
    /// Native elements fill the rest of the budget; indices are assigned after merging.
    private func collect(from window: AXUIElement) -> [ElementEntry] {
        var webAreas: [AXUIElement] = []
        let native = breadthFirst(
            from: [window], limit: maxElements, maxDepth: maxDepth, maxVisited: maxVisited,
            preferVisibleChildren: true, within: nil, deferWebAreas: &webAreas
        )

        var web: [ElementEntry] = []
        DebugLog.print("Crawl", "native pass: \(native.count) elements, \(webAreas.count) web area(s)")
        if !webAreas.isEmpty {
            var nested: [AXUIElement] = []
            web = breadthFirst(
                from: webAreas, limit: maxWebElements, maxDepth: maxWebDepth, maxVisited: maxWebVisited,
                preferVisibleChildren: false, within: window.frame(), deferWebAreas: &nested
            )
            DebugLog.print("Crawl", "web pass: \(web.count) elements")
        }

        let merged = native.prefix(maxElements - web.count) + web
        return merged.enumerated().map { $0.element.reindexed($0.offset) }
    }

    private func breadthFirst(
        from roots: [AXUIElement],
        limit: Int,
        maxDepth: Int,
        maxVisited: Int,
        preferVisibleChildren: Bool,
        within bounds: CGRect?,
        deferWebAreas webAreas: inout [AXUIElement]
    ) -> [ElementEntry] {
        var queue: [(AXUIElement, Int)] = roots.map { ($0, 0) }
        var head = 0
        var found: [ElementEntry] = []

        while head < queue.count, found.count < limit, head < maxVisited {
            let (element, depth) = queue[head]
            head += 1

            if preferVisibleChildren, depth > 0, let role: String = element.attribute(kAXRoleAttribute),
               role == Self.webAreaRole {
                webAreas.append(element)
                continue
            }

            if let observed = observe(element, index: found.count),
               bounds.map({ $0.intersects(observed.frame) }) ?? true {
                found.append(observed)
            }

            guard depth < maxDepth else { continue }
            let children: [AXUIElement] = (preferVisibleChildren ? element.attribute(kAXVisibleChildrenAttribute) : nil)
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
        let isControlRole = Self.actionableRoles.contains(role)
        guard isControlRole || !Self.pressActions.isDisjoint(with: actions) else { return nil }

        if let enabled: Bool = element.attribute(kAXEnabledAttribute), !enabled { return nil }

        let frame = element.frame()
        guard frame.width > 1, frame.height > 1 else { return nil }

        let entry = ElementEntry(
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
        // Elements admitted only because they're pressable (AXGroup, AXStaticText, …) must have a
        // label: unlabeled web wrappers are noise that crowds out real targets.
        guard isControlRole || entry.label != nil else { return nil }
        return entry
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
