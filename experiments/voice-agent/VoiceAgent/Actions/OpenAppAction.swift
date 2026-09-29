import AppKit

/// Installed applications, discovered by code. Jev picks a key from `criteria()`.
@MainActor
final class AppCatalog {
    private(set) var apps: [String: URL] = [:]

    static let searchRoots: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/Applications/Utilities"),
        URL(fileURLWithPath: "/System/Applications"),
        URL(fileURLWithPath: "/System/Applications/Utilities"),
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications"),
    ]

    init() {
        refresh()
    }

    func refresh() {
        var found: [String: URL] = [:]
        let fm = FileManager.default
        for root in Self.searchRoots {
            guard let items = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { continue }
            for url in items where url.pathExtension == "app" {
                let name = url.deletingPathExtension().lastPathComponent
                if found[name] == nil { found[name] = url }
            }
        }
        apps = found
    }

    func url(for name: String) -> URL? { apps[name] }

    /// Jev choice criteria. The description is the app name itself; Jev matches spoken
    /// variants ("chrome" → "Google Chrome") semantically.
    func criteria() -> [String: String] {
        Dictionary(uniqueKeysWithValues: apps.keys.map { ($0, "The \($0) app") })
    }
}

@MainActor
struct OpenAppAction: MacAction {
    func execute(_ request: ActionRequest, in context: ActionContext) async throws -> ActionResult {
        guard let name = request.appName else { throw ActionError.missingArgument("app") }
        guard let url = context.apps.url(for: name) else {
            return .failed("\(name) is not installed")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        return .ok("Opened \(name)")
    }
}
