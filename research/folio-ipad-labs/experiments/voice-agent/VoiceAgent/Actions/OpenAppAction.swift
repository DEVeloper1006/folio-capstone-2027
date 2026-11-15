import AppKit

/// Installed applications plus well-known websites, discovered and listed by code.
/// Jev picks a key from `criteria()`; `resolve(_:)` turns that key into something openable.
@MainActor
final class AppCatalog {
    enum Destination: Equatable {
        case app(URL)
        case website(URL)
    }

    struct Website {
        let name: String
        let url: URL
        let aliases: [String]
    }

    private(set) var apps: [String: URL] = [:]

    static let browserBundleIDs: Set<String> = [
        "com.apple.Safari", "com.google.Chrome", "company.thebrowser.Browser", "org.mozilla.firefox",
        "com.brave.Browser", "com.microsoft.edgemac", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]
    /// A browser opened this recently is where the next website goes ("open Safari and open YouTube").
    static let recentBrowserWindow: Duration = .seconds(30)

    private var lastOpenedBrowser: (url: URL, at: ContinuousClock.Instant)?
    /// App bundle that each website was last opened in, so the task loop can crawl it.
    private var websiteBrowsers: [URL: URL] = [:]

    static let searchRoots: [URL] = [
        URL(fileURLWithPath: "/Applications"),
        URL(fileURLWithPath: "/Applications/Utilities"),
        URL(fileURLWithPath: "/System/Applications"),
        URL(fileURLWithPath: "/System/Applications/Utilities"),
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Applications"),
    ]

    /// Spoken name → bundle identifier, for apps whose names people shorten or that live outside
    /// the scanned folders.
    static let bundleIDs: [String: String] = [
        "safari": "com.apple.Safari",
        "chrome": "com.google.Chrome",
        "google chrome": "com.google.Chrome",
        "firefox": "org.mozilla.firefox",
        "arc": "company.thebrowser.Browser",
        "mail": "com.apple.mail",
        "messages": "com.apple.MobileSMS",
        "notes": "com.apple.Notes",
        "calendar": "com.apple.iCal",
        "music": "com.apple.Music",
        "finder": "com.apple.finder",
        "system settings": "com.apple.systempreferences",
        "settings": "com.apple.systempreferences",
        "terminal": "com.apple.Terminal",
        "xcode": "com.apple.dt.Xcode",
        "slack": "com.tinyspeck.slackmacgap",
        "spotify": "com.spotify.client",
        "notion": "notion.id",
        "vs code": "com.microsoft.VSCode",
        "vscode": "com.microsoft.VSCode",
        "visual studio code": "com.microsoft.VSCode",
        "zoom": "us.zoom.xos",
        "discord": "com.hnc.Discord",
        "claude": "com.anthropic.claudefordesktop",
        "chatgpt": "com.openai.chat",
    ]

    /// Fallback when no local app matches: opened in the default browser.
    static let websites: [Website] = [
        Website(name: "YouTube", url: URL(string: "https://youtube.com")!, aliases: ["youtube"]),
        Website(name: "Gmail", url: URL(string: "https://gmail.com")!, aliases: ["gmail"]),
        Website(name: "X", url: URL(string: "https://x.com")!, aliases: ["x", "twitter"]),
        Website(name: "Reddit", url: URL(string: "https://reddit.com")!, aliases: ["reddit"]),
        Website(name: "Spotify", url: URL(string: "https://open.spotify.com")!, aliases: ["spotify"]),
        Website(name: "Slack", url: URL(string: "https://app.slack.com")!, aliases: ["slack"]),
        Website(name: "Notion", url: URL(string: "https://notion.so")!, aliases: ["notion"]),
        Website(name: "GitHub", url: URL(string: "https://github.com")!, aliases: ["github"]),
        Website(name: "Netflix", url: URL(string: "https://netflix.com")!, aliases: ["netflix"]),
        Website(name: "ChatGPT", url: URL(string: "https://chatgpt.com")!, aliases: ["chatgpt"]),
        Website(name: "Claude", url: URL(string: "https://claude.ai")!, aliases: ["claude"]),
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

    /// 1. bundle-ID map → 2. installed app by name → 3. website map. Nil if nothing matches.
    func resolve(_ name: String) -> Destination? {
        let key = name.trimmingCharacters(in: .whitespaces).lowercased()
        if let bundleID = Self.bundleIDs[key],
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return .app(url)
        }
        if let url = apps[name] ?? apps.first(where: { $0.key.lowercased() == key })?.value {
            return .app(url)
        }
        if let site = Self.websites.first(where: { $0.name.lowercased() == key || $0.aliases.contains(key) }) {
            return .website(site.url)
        }
        return nil
    }

    /// Records an opened app; browsers become the target for websites opened soon after.
    func noteOpened(app url: URL) {
        guard let id = Bundle(url: url)?.bundleIdentifier, Self.browserBundleIDs.contains(id) else { return }
        lastOpenedBrowser = (url, .now)
    }

    /// Browser for a website: one opened in the last `recentBrowserWindow`, else the frontmost app if
    /// it's a browser, else nil (the default browser).
    func browser(forWebsite url: URL) -> URL? {
        if let recent = lastOpenedBrowser, ContinuousClock.now - recent.at < Self.recentBrowserWindow {
            return recent.url
        }
        if let pid = AXTreeCrawler.frontmostOtherAppPID(),
           let app = NSRunningApplication(processIdentifier: pid),
           let id = app.bundleIdentifier, Self.browserBundleIDs.contains(id) {
            return app.bundleURL
        }
        return nil
    }

    func noteOpened(website url: URL, in browser: URL?) {
        websiteBrowsers[url] = browser ?? NSWorkspace.shared.urlForApplication(toOpen: url)
    }

    /// Running process for an app or website name after OPEN_APP (for a website, its browser).
    func runningPID(for name: String) -> pid_t? {
        let bundle: URL? = switch resolve(name) {
        case .app(let url): url
        case .website(let url): websiteBrowsers[url] ?? NSWorkspace.shared.urlForApplication(toOpen: url)
        case nil: nil
        }
        guard let bundle else { return nil }
        return NSWorkspace.shared.runningApplications.first { $0.bundleURL?.standardizedFileURL == bundle.standardizedFileURL }?.processIdentifier
    }

    /// Jev choice criteria: installed apps, plus websites that don't share a name with one.
    func criteria() -> [String: String] {
        var criteria = Dictionary(uniqueKeysWithValues: apps.keys.map { ($0, "The \($0) app") })
        let installed = Set(apps.keys.map { $0.lowercased() })
        for site in Self.websites where !installed.contains(site.name.lowercased()) {
            let alias = site.aliases.count > 1 ? " (also called \(site.aliases.dropFirst().joined(separator: ", ")))" : ""
            criteria[site.name] = "The \(site.name) website\(alias), opened in the browser"
        }
        return criteria
    }
}

@MainActor
struct OpenAppAction: MacAction {
    func execute(_ request: ActionRequest, in context: ActionContext) async throws -> ActionResult {
        guard let name = request.appName else { throw ActionError.missingArgument("app") }
        switch context.apps.resolve(name) {
        case .app(let url):
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            context.apps.noteOpened(app: url)
            return .ok("Opened \(url.deletingPathExtension().lastPathComponent)")
        case .website(let url):
            let site = AppCatalog.websites.first { $0.url == url }?.name ?? name
            if let browser = context.apps.browser(forWebsite: url) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                _ = try await NSWorkspace.shared.open([url], withApplicationAt: browser, configuration: configuration)
                context.apps.noteOpened(website: url, in: browser)
                return .ok("Opened \(site) in \(browser.deletingPathExtension().lastPathComponent)")
            }
            guard NSWorkspace.shared.open(url) else { return .failed("Couldn't open \(name) in the browser") }
            context.apps.noteOpened(website: url, in: nil)
            return .ok("Opened \(site)")
        case nil:
            return .failed("I couldn't find \(name) as an app or website")
        }
    }
}
