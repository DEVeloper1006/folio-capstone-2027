import Cocoa
import WebKit
import UniformTypeIdentifiers

@MainActor
final class FolioApp: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var latestState: Data?
    private var saveError = false
    private var ready = false
    private var terminating = false
    private let assistant = MathAssistant()
    private var assistantTask: Task<Void, Never>?
    private var modeTask: Task<Void, Never>?
    private var modeRequestID: String?
    private let testing = CommandLine.arguments.contains("--self-test")
    private var recoveryURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Folio/workspace.folio")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !testing, let bundle = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            existing.activate(options: [.activateIgnoringOtherApps])
            NSApp.terminate(nil)
            return
        }
        do { try launch() }
        catch { showError(error); NSApp.terminate(nil) }
    }

    private func launch() throws {
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "folio")
        if testing {
            config.websiteDataStore = .nonPersistent()
            config.userContentController.addUserScript(WKUserScript(source: "window.FolioTesting = true", injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        if !testing && FileManager.default.fileExists(atPath: recoveryURL.path) {
            do {
                let data = try WorkspaceStore(url: recoveryURL).read()
                guard let json = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
                config.userContentController.addUserScript(WKUserScript(
                    source: "window.FolioInitialState = \(json);", injectionTime: .atDocumentStart, forMainFrameOnly: true))
                latestState = data
            } catch {
                let alert = NSAlert()
                alert.messageText = "The saved workspace could not be opened."
                alert.informativeText = "Your original file is unchanged. You can quit, or keep an untouched recovery copy and start an empty workspace."
                alert.addButton(withTitle: "Quit")
                alert.addButton(withTitle: "Keep Recovery Copy & Start Empty")
                guard alert.runModal() == .alertSecondButtonReturn else { throw error }
                _ = try WorkspaceStore(url: recoveryURL).recoveryCopy()
                let empty = EditorState(document: "", current: "linalg", registers: [:], metadata: ["title": "Untitled Assignment", "student": "", "course": "", "date": ""])
                let json = String(decoding: try JSONEncoder().encode(empty), as: UTF8.self)
                config.userContentController.addUserScript(WKUserScript(source: "window.FolioInitialState = \(json);", injectionTime: .atDocumentStart, forMainFrameOnly: true))
            }
        }
        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = testing ? "Folio — Verification" : "Folio"
        window.minSize = NSSize(width: 520, height: 360)
        window.contentView = webView
        window.delegate = self
        window.isReleasedWhenClosed = false
        if !testing { window.setFrameAutosaveName("FolioWorkspace") }
        window.center()
        buildMenu()
        guard let root = Bundle.main.resourceURL?.appendingPathComponent("editor") else { throw CocoaError(.fileNoSuchFile) }
        webView.loadFileURL(root.appendingPathComponent("desktop.html"), allowingReadAccessTo: root)
        if !testing {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.frameInfo.request.url?.isFileURL == true,
              let body = message.body as? [String: Any], let action = body["action"] as? String else { return }
        do {
            switch action {
            case "persist":
                guard let json = body["state"] as? String else { throw CocoaError(.fileWriteInapplicableStringEncoding) }
                let data = Data(json.utf8)
                try persist(data)
                if ready { evaluate("window.Folio.saved()") }
            case "ready":
                ready = true
                evaluate("window.Folio.saved()")
                if testing { runSelfTest() }
            case "export":
                guard let content = body["content"] as? String, let filename = body["filename"] as? String else { return }
                savePanel(data: Data(content.utf8), filename: filename)
            case "print":
                let operation = webView.printOperation(with: NSPrintInfo.shared)
                operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
            case "quit": NSApp.terminate(nil)
            case "models":
                let forModes = body["target"] as? String == "modes"
                Task {
                    do {
                        let models = try await assistant.models()
                        if forModes { try await deliverMode(["models": models]) }
                        else { try await deliverAssistant(["models": models]) }
                    }
                    catch {
                        if forModes { try? await deliverMode(["error": error.localizedDescription]) }
                        else { await deliverAssistantError(error) }
                    }
                }
            case "mathMode":
                guard let id = body["id"] as? String, let model = body["model"] as? String,
                      let passage = body["passage"] as? String, let current = body["current"] as? String,
                      let catalog = body["catalog"] as? String, let topic = body["topic"] as? String else { return }
                let available = try JSONDecoder().decode([ModeSummary].self, from: Data(catalog.utf8))
                guard available.count <= 67, available.contains(where: { $0.id == current }), topic.count <= 200 else { return }
                modeTask?.cancel()
                modeRequestID = id
                modeTask = Task {
                    defer { if modeRequestID == id { modeTask = nil; modeRequestID = nil } }
                    do {
                        var subject = topic
                        var reason = "Created from your requested subject."
                        if subject.isEmpty {
                            let decision = try await assistant.recognize(model: model, context: passage, current: current, available: available)
                            if testing { FileHandle.standardOutput.write(Data(("Recognized: " + String(decoding: try JSONEncoder().encode(decision), as: UTF8.self) + "\n").utf8)) }
                            try Task.checkCancellation()
                            if decision.action != .create {
                                try await deliverMode(["id": id, "decision": String(decoding: try JSONEncoder().encode(decision), as: UTF8.self)])
                                return
                            }
                            subject = decision.topic
                            reason = decision.reason
                        }
                        try await deliverMode(["id": id, "status": "Creating \(subject) bindings…"])
                        let draft = try await assistant.draftMode(model: model, topic: subject)
                        if testing { FileHandle.standardOutput.write(Data(("Mode draft: " + String(decoding: try JSONEncoder().encode(draft), as: UTF8.self) + "\n").utf8)) }
                        let mode = try draft.materialize()
                        try Task.checkCancellation()
                        try await deliverMode(["id": id, "mode": String(decoding: try JSONEncoder().encode(mode), as: UTF8.self), "reason": reason])
                    } catch {
                        if !Task.isCancelled { try? await deliverMode(["id": id, "error": error.localizedDescription]) }
                    }
                }
            case "cancelMathMode":
                modeTask?.cancel()
                modeRequestID = nil
            case "assistant":
                guard let id = body["id"] as? String, let model = body["model"] as? String,
                      let request = body["request"] as? String, let document = body["document"] as? String,
                      let mode = body["mode"] as? String, let selection = body["selection"] as? String,
                      let intent = body["intent"] as? String,
                      ["step", "hint"].contains(intent), !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                guard assistantTask == nil else {
                    Task {
                        do { try await deliverAssistant(["id": id, "error": "The previous request is still stopping. Try again in a moment."]) }
                        catch { showError(error) }
                    }
                    return
                }
                assistantTask = Task {
                    defer { assistantTask = nil }
                    do {
                        let state = try latestState.map { try JSONDecoder().decode(EditorState.self, from: $0) }
                        let available = MathMode.builtinIDs + (state?.modes ?? []).map(\.id)
                        let names = Dictionary(uniqueKeysWithValues: (state?.modes ?? []).map { ($0.id, $0.title) })
                        let proposal = try await assistant.propose(model: model, request: request, document: document, mode: mode, selection: selection, intent: intent, allowedModes: available, modeNames: names)
                        let json = String(decoding: try JSONEncoder().encode(proposal), as: UTF8.self)
                        try await deliverAssistant(["id": id, "proposal": json])
                    } catch { await deliverAssistantError(error, id: id) }
                }
            case "cancelAssistant":
                assistantTask?.cancel()
            default: break
            }
        } catch {
            if action == "persist" {
                evaluate("window.Folio?.message('Save failed — keep this window open and use Save As')")
                if !saveError { showError(error) }
                saveError = true
            } else { showError(error) }
        }
    }

    private func persist(_ data: Data) throws {
        if testing { try JSONDecoder().decode(EditorState.self, from: data).validate() }
        else { try WorkspaceStore(url: recoveryURL).write(data) }
        latestState = data
        saveError = false
    }

    private func deliverAssistant(_ result: [String: Any]) async throws {
        _ = try await webView.callAsyncJavaScript("window.Folio.assistantResult(result)", arguments: ["result": result], in: nil, contentWorld: .page)
    }

    private func deliverMode(_ result: [String: Any]) async throws {
        if testing, let mode = result["mode"] as? String {
            FileHandle.standardOutput.write(Data(("Generated mode: " + mode + "\n").utf8))
        }
        _ = try await webView.callAsyncJavaScript("return window.Folio.modeResult(result)", arguments: ["result": result], in: nil, contentWorld: .page)
    }

    private func deliverAssistantError(_ error: Error, id: String = "") async {
        do { try await deliverAssistant(["id": id, "error": error.localizedDescription]) }
        catch { showError(error) }
    }

    private func evaluate(_ source: String) {
        webView.evaluateJavaScript(source) { [weak self] _, error in
            if let error { self?.showError(error) }
        }
    }

    private func showError(_ error: Error) {
        if testing { fputs("Folio verification failed: \(error)\n", stderr); exit(1) }
        NSAlert(error: error).runModal()
    }

    private func savePanel(data: Data, filename: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url, options: .atomic)
                self?.evaluate("window.Folio.message('Saved to file')")
            } catch { self?.showError(error) }
        }
    }

    @objc private func saveDocument() {
        guard ready else { return }
        Task {
            do {
                let value = try await webView.callAsyncJavaScript("return JSON.stringify(window.Folio.state())", arguments: [:], in: nil, contentWorld: .page)
                guard let json = value as? String else { throw CocoaError(.fileWriteUnknown) }
                let data = Data(json.utf8)
                try persist(data)
                savePanel(data: data, filename: "workspace.folio")
            } catch { showError(error) }
        }
    }

    @objc private func openDocument() {
        guard ready else { return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .json, UTType(filenameExtension: "folio") ?? .data, UTType(filenameExtension: "tex") ?? .plainText]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                let data = try Data(contentsOf: url)
                let state: EditorState
                if ["folio", "json"].contains(url.pathExtension.lowercased()) {
                    state = try JSONDecoder().decode(EditorState.self, from: data)
                    try state.validate()
                } else {
                    guard let text = String(data: data, encoding: .utf8), let current = self.latestState else {
                        throw CocoaError(.fileReadInapplicableStringEncoding)
                    }
                    let old = try JSONDecoder().decode(EditorState.self, from: current)
                    state = EditorState(document: text, current: old.current, registers: old.registers, metadata: old.metadata, modes: old.modes, preferences: old.preferences)
                }
                let alert = NSAlert()
                alert.messageText = "Open this document?"
                alert.informativeText = "This replaces the active workspace. Save it first if you need a separate copy. Undo will also restore the previous text."
                alert.addButton(withTitle: "Open")
                alert.addButton(withTitle: "Cancel")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
                let json = String(decoding: try JSONEncoder().encode(state), as: UTF8.self)
                self.webView.callAsyncJavaScript("window.Folio.importState(JSON.parse(json));", arguments: ["json": json], in: nil, in: .page) { result in
                    if case .failure(let error) = result { self.showError(error) }
                }
            } catch { self.showError(error) }
        }
    }

    @objc private func command(_ sender: NSMenuItem) {
        guard ready, let command = sender.representedObject as? String else { return }
        webView.callAsyncJavaScript("window.Folio.command(command)", arguments: ["command": command], in: nil, in: .page) { [weak self] result in
            if case .failure(let error) = result { self?.showError(error) }
        }
    }

    private func buildMenu() {
        let main = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            item.submenu = menu
            main.addItem(item)
            return menu
        }
        func item(_ menu: NSMenu, _ title: String, _ key: String, _ action: Selector, command: String? = nil) {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
            entry.target = self
            entry.representedObject = command
            menu.addItem(entry)
        }
        let app = submenu("Folio")
        app.addItem(withTitle: "About Folio", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Quit Folio", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let file = submenu("File")
        item(file, "Open…", "o", #selector(openDocument))
        item(file, "Save As…", "s", #selector(saveDocument))
        item(file, "Export…", "e", #selector(command(_:)), command: "export")
        item(file, "Print…", "p", #selector(command(_:)), command: "export pdf")
        let edit = submenu("Edit")
        item(edit, "Undo", "z", #selector(command(_:)), command: "undo")
        item(edit, "Redo", "Z", #selector(command(_:)), command: "redo")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let view = submenu("View")
        item(view, "Toggle LaTeX Preview", "\\", #selector(command(_:)), command: "preview")
        let modes = submenu("Math")
        item(modes, "Math Modes & Bindings…", "", #selector(command(_:)), command: "modes")
        item(modes, "Detect Math Now", "D", #selector(command(_:)), command: "detect")
        item(modes, "Toggle Automatic Modes", "", #selector(command(_:)), command: "auto")
        modes.addItem(.separator())
        item(modes, "Linear Algebra", "1", #selector(command(_:)), command: "M linalg")
        item(modes, "Calculus", "2", #selector(command(_:)), command: "M calculus")
        item(modes, "Proof", "3", #selector(command(_:)), command: "M proof")
        modes.addItem(.separator())
        item(modes, "Translate a Step…", "", #selector(command(_:)), command: "step")
        item(modes, "Ask for a Hint…", "", #selector(command(_:)), command: "hint")
        let help = submenu("Help")
        item(help, "Folio Commands", "?", #selector(command(_:)), command: "help")
        NSApp.mainMenu = main
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        // Only bundled content can receive the native file bridge.
        let expected = Bundle.main.resourceURL?.appendingPathComponent("editor/desktop.html")
        let allowed = navigationAction.request.url?.standardizedFileURL == expected?.standardizedFileURL
        if testing { print("Navigation: \(navigationAction.request.url?.absoluteString ?? "nil"); allowed: \(allowed)") }
        decisionHandler(allowed ? .allow : .cancel)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { showError(error) }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor (Bool) -> Void) {
        guard frame.isMainFrame, frame.request.url?.isFileURL == true else { completionHandler(false); return }
        let alert = NSAlert()
        alert.messageText = "Folio"
        alert.informativeText = message
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Continue")
        completionHandler(alert.runModal() == .alertSecondButtonReturn)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { showError(error) }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if testing && !ready {
            webView.evaluateJavaScript("JSON.stringify({title: document.title, bridge: !!window.webkit?.messageHandlers.folio, editor: !!window.Folio, initial: window.FolioInitialState})") { value, error in
                print("Not ready: \(String(describing: value)); \(String(describing: error))")
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard ready else { return .terminateNow }
        guard !terminating else { return .terminateLater }
        terminating = true
        Task {
            do {
                // Drain the web editor before exit; an input message may still be in flight.
                let result = try await webView.callAsyncJavaScript("return JSON.stringify(window.Folio.state())", arguments: [:], in: nil, contentWorld: .page)
                guard let json = result as? String else { throw CocoaError(.fileWriteUnknown) }
                try persist(Data(json.utf8))
                NSApp.reply(toApplicationShouldTerminate: true)
            } catch {
                terminating = false
                saveError = true
                showError(error)
                NSApp.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }

    private func runSelfTest() {
        webView.callAsyncJavaScript("""
        const check = (condition, message) => { if (!condition) throw Error(message); };
        const input = document.querySelector('#editor');
        check(document.documentElement.classList.contains('native'), 'native layout missing');
        check(getComputedStyle(document.querySelector('.inspect')).display === 'none', 'inspector visible');
        window.Folio.importState({document: '$x^2$', current: 'calculus'});
        window.Folio.command('M proof');
        check(window.Folio.state().document === '$x^2$', 'mode switch changed document');
        input.dispatchEvent(new KeyboardEvent('keydown', {key: 'i', bubbles: true}));
        check(!input.readOnly, 'Insert mode failed');
        input.value = '$x^2$\\n$y = x$';
        input.dispatchEvent(new InputEvent('input', {bubbles: true}));
        input.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', bubbles: true}));
        check(input.readOnly, 'Normal mode failed');
        input.dispatchEvent(new KeyboardEvent('keydown', {key: 'u', bubbles: true}));
        check(input.value === '$x^2$', 'undo failed');
        window.Folio.command('preview');
        check(document.querySelector('.preview-pane').getBoundingClientRect().height > 0, 'preview is hidden');
        window.Folio.command('preview');
        check(input.getBoundingClientRect().height > 0, 'source did not reappear');
        window.Folio.command('preview');
        window.Folio.command('help');
        check(document.querySelector('#help-dialog').open, 'help did not open');
        document.querySelector('#help-dialog').close();
        await new Promise(resolve => setTimeout(resolve, 200));
        await MathJax.startup.promise;
        await MathJax.typesetPromise([document.querySelector('#preview-body')]);
        check(!!document.querySelector('#preview-body mjx-container svg'), 'LaTeX did not render');
        window.Folio.command('M calculus');
        window.Folio.command('preview');
        input.setSelectionRange(input.value.length, input.value.length);
        input.dispatchEvent(new KeyboardEvent('keydown', {key: String.fromCharCode(92), bubbles: true}));
        input.dispatchEvent(new KeyboardEvent('keydown', {key: 't', bubbles: true}));
        check(input.value.includes('frac{d}{dx}'), 'calculus macro failed');
        window.Folio.command('undo');
        check(input.value === '$x^2$', 'macro could not be undone');
        const press = key => input.dispatchEvent(new KeyboardEvent('keydown', {key, bubbles: true}));
        for (const key of ['s', 'o', 'm', 'q']) {
          const shortcut = new KeyboardEvent('keydown', {key, metaKey: true, bubbles: true, cancelable: true});
          input.dispatchEvent(shortcut);
          check(!shortcut.defaultPrevented, 'native Command-' + key + ' was swallowed by the editor');
        }
        window.Folio.importState({document: 'abcd', current: 'linalg'});
        input.setSelectionRange(4, 4);
        press('v'); press('h'); press('h'); press('h');
        check(input.selectionStart === 1 && input.selectionEnd === 4, 'backward visual selection stopped after one character');
        press('Escape');
        window.Folio.importState({document: 'one', current: 'linalg'});
        press('y'); press('y'); press('p');
        check(input.value === 'one\\none', 'linewise paste joined the final lines');
        press('u');
        check(input.value === 'one', 'line paste undo failed');
        window.Folio.importState({document: 'one', current: 'linalg', registers: {a: ['@', 'a']}});
        press('@'); press('a');
        check(document.querySelector('#message').textContent.includes('recursive'), 'recursive register was not stopped');
        press('l');
        check(input.selectionStart === 1, 'editor stopped responding after recursive register');
        const multiline = '$$\\n' + String.raw`\\begin{bmatrix}1 & 0 \\\\ 0 & 1\\end{bmatrix}` + '\\n$$';
        window.Folio.importState({document: multiline, current: 'linalg'});
        await new Promise(resolve => setTimeout(resolve, 200));
        await typesetQueue;
        check(document.querySelectorAll('#preview-body mjx-container').length === 1, 'multiline display math split apart');
        check(!document.querySelector('#preview-body [data-mjx-error], #preview-body [data-mml-node="merror"]'), 'multiline matrix did not render');
        const mathItems = Array.from(MathJax.startup.document.math).length;
        for (let repeat = 0; repeat < 5; repeat++) {
            renderPreview();
            await new Promise(resolve => setTimeout(resolve, 100));
            await typesetQueue;
        }
        check(Array.from(MathJax.startup.document.math).length === mathItems, 'repeated rendering leaked detached math items');
        const invalidNotation = await MathJax.tex2svgPromise(String.raw`\\langlex`);
        check(!!invalidNotation.querySelector('[data-mjx-error], [data-mml-node="merror"]'), 'unknown TeX command was silently accepted');
        check(toLatex().includes(String.raw`\\begin{bmatrix}1 & 0 \\\\ 0 & 1\\end{bmatrix}`), 'LaTeX export changed matrix source');
        window.Folio.importState({document: 'Proof:\\n$P$\\n∎', current: 'proof'});
        check(toLatex().includes(String.raw`\\begin{proof}`) && toLatex().includes(String.raw`\\end{proof}`), 'proof export missing its environment');
        window.Folio.importState({document: '∎', current: 'proof'});
        check(!toLatex().includes(String.raw`\\end{proof}`), 'QED emitted an unmatched proof environment');
        const priorState = JSON.stringify(window.Folio.state());
        let rejected = false;
        try { window.Folio.importState({document: 'bad import', current: 'missing-mode'}); } catch { rejected = true; }
        check(rejected && JSON.stringify(window.Folio.state()) === priorState, 'invalid import partially changed workspace');
        window.Folio.importState({document: '$x^2$', current: 'calculus'});
        const waitFor = async predicate => {
            const until = Date.now() + 600000;
            while (!predicate()) {
                check(Date.now() < until, 'live assistant timed out: ' + document.querySelector('#mode-status').textContent);
                await new Promise(resolve => setTimeout(resolve, 100));
            }
        };
        const liveModesResult = [];
        if (liveModes) {
            window.Folio.command('modes');
            await waitFor(() => !document.querySelector('#mode-model').disabled);
            const select = document.querySelector('#mode-model');
            if (modelName) { select.value = modelName; check(select.value === modelName, 'requested model not installed'); }
            select.dispatchEvent(new Event('change', {bubbles: true}));
            const selectedModel = select.value;
            document.querySelector('#modes-dialog').close();
            for (const passage of [
                '# Quaternion rotation\\n$q = a + bi + cj + dk$\\nConjugate the quaternion and compose noncommutative rotations.',
                '# Qubits\\nA qubit has state alpha |0> + beta |1>. Apply quantum gates and work with bra-ket inner products.',
                '# Complex analysis\\nCompute residues of meromorphic functions and integrate along closed contours in the complex plane.'
            ]) {
                window.Folio.importState({document: passage, current: 'linalg', preferences: {automatic: true, model: selectedModel}});
                input.setSelectionRange(input.value.length, input.value.length);
                const count = window.Folio.state().modes.length;
                input.dispatchEvent(new KeyboardEvent('keyup', {key: 'Escape', bubbles: true}));
                await waitFor(() => !!modePending);
                await waitFor(() => !modePending);
                const state = window.Folio.state();
                check(state.modes.length === count + 1, 'automatic mode not created: ' + document.querySelector('#mode-status').textContent);
                const created = state.modes.find(mode => mode.id === state.current);
                check(!!created && input.value === passage, 'automatic mode changed source or did not activate');
                const binding = created.bindings[0];
                press(String.fromCharCode(92)); press(binding.key);
                check(!input.readOnly && input.value.length > passage.length && !input.value.includes('{{cursor}}'), 'generated keybinding did not insert editable notation');
                press('Escape'); press('u');
                check(input.value === passage, 'generated binding undo changed original work');
                window.Folio.command('M linalg');
                window.Folio.command('detect');
                await waitFor(() => !modePending);
                check(window.Folio.state().current === created.id && window.Folio.state().modes.length === count + 1, 'existing generated mode was not reused');
                const roundTrip = JSON.parse(JSON.stringify(window.Folio.state()));
                roundTrip.modes = roundTrip.modes.map(mode => ({bindings: mode.bindings.map(binding => ({after: binding.after, before: binding.before, label: binding.label, key: binding.key})), summary: mode.summary, title: mode.title, id: mode.id}));
                window.Folio.importState(roundTrip);
                check(window.Folio.state().current === created.id, 'custom mode failed workspace round-trip');
                liveModesResult.push(created);
            }
        }
        let liveProposal = null;
        if (liveAssistant) {
            window.Folio.importState({document: '$x^2$', current: 'linalg'});
            const waitFor = async predicate => {
                const until = Date.now() + 180000;
                while (!predicate()) {
                    check(Date.now() < until, 'live assistant timed out');
                    await new Promise(resolve => setTimeout(resolve, 100));
                }
            };
            window.Folio.command('M linalg');
            window.Folio.command('auto on');
            window.Folio.command('step Apply the power rule to x^2 to write d/dx(x^2) = 2x. Switch to calculus mode. Write only this one step.');
            const send = document.querySelector('#assistant-send');
            const accept = document.querySelector('#assistant-accept');
            await waitFor(() => !send.disabled);
            if (modelName) {
                const model = document.querySelector('#assistant-model');
                model.value = modelName;
                check(model.value === modelName, 'requested assistant model not installed');
                model.dispatchEvent(new Event('change', {bubbles: true}));
            }
            send.click();
            await waitFor(() => !send.disabled);
            check(!accept.hidden, document.querySelector('#assistant-status').textContent);
            liveProposal = document.querySelector('#assistant-latex').textContent;
            check(liveProposal.length > 0, 'no live mathematical proposal');
            await MathJax.typesetPromise([document.querySelector('#assistant-preview')]);
            check(!!document.querySelector('#assistant-preview mjx-container svg'), 'proposal did not render');
            check(!document.querySelector('#assistant-preview [data-mjx-error]'), 'invalid LaTeX in proposal');
            check(input.value === '$x^2$', 'proposal edited before acceptance');
            accept.click();
            check(input.value === '$x^2$\\n' + liveProposal, 'accepted step not appended');
            check(window.Folio.state().current === 'calculus', 'accepted mode not applied');
            check(!window.Folio.state().preferences.automatic, 'accepted mode choice was not pinned');
            window.Folio.command('undo');
            check(input.value === '$x^2$', 'accepted step could not be undone');
            window.Folio.command('step Switch to proof mode without changing any mathematics.');
            await waitFor(() => !send.disabled);
            send.click();
            await waitFor(() => !send.disabled);
            check(!accept.hidden, document.querySelector('#assistant-status').textContent);
            window.Folio.command('M linalg');
            accept.click();
            check(document.querySelector('#assistant-dialog').open, 'stale proposal was accepted');
            check(document.querySelector('#assistant-status').textContent.includes('changed'), 'stale proposal warning missing');
            check(input.value === '$x^2$' && window.Folio.state().current === 'linalg', 'stale proposal changed workspace');
            document.querySelector('#assistant-dialog').close();
        }
        return JSON.stringify({native: true, modes: true, editing: true, undo: true, help: true, latex: true, regressionChecks: true, liveProposal, liveModesResult});
        """, arguments: ["liveAssistant": CommandLine.arguments.contains("--live-assistant"),
                         "liveModes": CommandLine.arguments.contains("--live-modes"),
                         "modelName": CommandLine.arguments.firstIndex(of: "--model").flatMap { index in index + 1 < CommandLine.arguments.count ? CommandLine.arguments[index + 1] : nil } ?? ""], in: nil, in: .page) { result in
            switch result {
            case .success(let value): print(value); exit(0)
            case .failure(let error): self.showError(error)
            }
        }
    }
}

@main
struct FolioMain {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = FolioApp()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}
