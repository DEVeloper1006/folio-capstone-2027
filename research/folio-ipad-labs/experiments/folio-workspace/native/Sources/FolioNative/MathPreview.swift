import SwiftUI
import WebKit
import FolioCore

struct ShadowView: View {
    let node: ShadowNode
    var body: some View {
        switch node {
        case .symbol(let value, _): Text(value).font(.system(size: 28, design: .serif))
        case .hole: Text("□").font(.title2).accessibilityLabel("Unfinished expression")
        case .ink(let strokes):
            Canvas { context, size in
                let box = StrokeGeometry.bounds(of: strokes).insetBy(dx: -3, dy: -3)
                let scale = min(size.width / box.width, size.height / box.height)
                for s in strokes {
                    var path = Path()
                    for (i,p) in s.points.enumerated() {
                        let point = CGPoint(x: (p.x-box.minX)*scale, y: (p.y-box.minY)*scale)
                        if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    if s.points.count == 1, let p = s.points.first {
                        path.addLine(to: CGPoint(x: (p.x-box.minX)*scale + 0.1, y: (p.y-box.minY)*scale + 0.1))
                    }
                    context.stroke(path, with: .color(Color(red: 0.15, green: 0.29, blue: 0.45)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
            .frame(width: min(160, max(24, StrokeGeometry.bounds(of: strokes).width * 0.65)), height: 44)
            .accessibilityLabel("Unresolved handwriting. Select the row to correct it.")
        case .row(let children):
            HStack(spacing: 8) {
                ForEach(Array(children.enumerated()), id: \.offset) { _, child in
                    AnyView(ShadowView(node: child))
                }
            }
        case .fraction(let top, let bottom, _):
            VStack(spacing: 4) {
                AnyView(ShadowView(node: top))
                Rectangle().frame(height: 1).frame(minWidth: 48)
                AnyView(ShadowView(node: bottom))
            }.fixedSize()
        }
    }
}

func resourceURL() -> URL? {
    #if SWIFT_PACKAGE
    return Bundle.module.url(forResource: "Math", withExtension: nil)
    #else
    return Bundle.main.url(forResource: "Math", withExtension: nil)
    #endif
}

/// Keep the actual recognized text visible until the web renderer confirms it
/// has rendered this revision. Failures must never become blank white boxes.
struct MathPreview: View {
    let latex: String
    @State private var renderedLatex: String?
    @State private var failure: String?
    var body: some View {
        ZStack(alignment: .topLeading) {
            MathWebView(latex: latex) { value, error in
                renderedLatex = error == nil ? value : nil
                failure = error
            }
            .opacity(renderedLatex == latex ? 1 : 0)
            .allowsHitTesting(renderedLatex == latex)
            if renderedLatex != latex {
                VStack(alignment: .leading, spacing: 8) {
                    Text(latex).font(.system(size: 24, design: .serif))
                        .textSelection(.enabled)
                    Text(failure == nil ? "Typesetting..." : "Showing LaTeX. Typesetting unavailable.")
                        .font(.caption).foregroundStyle(Color(red: 0.35, green: 0.40, blue: 0.42))
                }
                .foregroundStyle(Color(red: 0.15, green: 0.18, blue: 0.20))
                .padding(16)
            }
        }.background(Color.white)
    }
}

@MainActor final class MathRenderState: NSObject, WKNavigationDelegate {
    var latest = ""
    var ready = false
    var revision = 0
    var onResult: (String, String?) -> Void = { _, _ in }
    private var watchdog: Task<Void, Never>?

    func start(_ view: WKWebView) {
        view.navigationDelegate = self
        guard let directory = resourceURL() else {
            onResult(latest, "Missing math resources"); return
        }
        let file = directory.appendingPathComponent("math.html")
        guard FileManager.default.fileExists(atPath: file.path) else {
            onResult(latest, "Missing math renderer"); return
        }
        // loadHTMLString(baseURL:) does not grant a packaged app access to
        // adjacent JavaScript/fonts. A file navigation grants the exact folder.
        view.loadFileURL(file, allowingReadAccessTo: directory)
        watchdog = Task { [weak self, weak view] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self, !self.ready else { return }
            view?.stopLoading()
            self.onResult(self.latest, "Math renderer did not load")
        }
    }

    func update(_ latex: String, in view: WKWebView) {
        if latest != latex { latest = latex; revision += 1 }
        if ready { render(in: view) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        watchdog?.cancel()
        ready = true
        render(in: webView)
    }

    private var submittedRevision = -1
    private func render(in view: WKWebView) {
        guard submittedRevision != revision else { return }
        submittedRevision = revision
        let version = revision, value = latest
        Task { [weak self, weak view] in
            guard let view else { return }
            do {
                let payload = try await view.callAsyncJavaScript(
                    "return await window.renderMath(latex);",
                    arguments: ["latex": value], in: nil, contentWorld: .page
                )
                guard let self, version == self.revision else { return }
                let result = payload as? [String: Any]
                self.onResult(value, result?["ok"] as? Bool == true ? nil : (result?["error"] as? String ?? "Could not typeset expression"))
            } catch {
                guard let self, version == self.revision else { return }
                self.onResult(value, error.localizedDescription)
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        watchdog?.cancel(); ready = false
        onResult(latest, error.localizedDescription)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        watchdog?.cancel(); ready = false
        onResult(latest, error.localizedDescription)
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        ready = false; submittedRevision = -1
        onResult(latest, "Math renderer stopped")
    }
}

#if os(iOS)
struct MathWebView: UIViewRepresentable {
    let latex: String
    let onResult: (String, String?) -> Void
    func makeCoordinator() -> MathRenderState { MathRenderState() }
    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        context.coordinator.latest = latex
        context.coordinator.onResult = onResult
        context.coordinator.start(view)
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.onResult = onResult
        context.coordinator.update(latex, in: view)
    }
}
#else
struct MathWebView: NSViewRepresentable {
    let latex: String
    let onResult: (String, String?) -> Void
    func makeCoordinator() -> MathRenderState { MathRenderState() }
    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.underPageBackgroundColor = .white
        context.coordinator.latest = latex
        context.coordinator.onResult = onResult
        context.coordinator.start(view)
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onResult = onResult
        context.coordinator.update(latex, in: view)
    }
}
#endif
