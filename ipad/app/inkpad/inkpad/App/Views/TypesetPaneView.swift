import SwiftUI
import WebKit

struct TypesetPaneView: View {
    let steps: [TypesetStep]
    @Binding var isPresented: Bool
    let orientation: UIDeviceOrientation

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            MathJaxWebView(steps: steps)
        }
        .background(FolioTheme.chromeBackground)
    }

    private var header: some View {
        HStack {
            Text("Typeset")
                .font(FolioTheme.uiFont(size: 16, weight: .semibold))

            Spacer()

            Button {
                UIPasteboard.general.string = steps.map(\.latex).joined(separator: "\n")
            } label: {
                Text("LaTeX")
                    .font(FolioTheme.uiFont(size: 13, weight: .medium))
                    .foregroundStyle(FolioTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().stroke(FolioTheme.accent, lineWidth: 1)
                    )
            }

            Button {
                UIPasteboard.general.string = steps.map(\.markdown).joined(separator: "\n\n")
            } label: {
                Text("Markdown")
                    .font(FolioTheme.uiFont(size: 13, weight: .medium))
                    .foregroundStyle(FolioTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().stroke(FolioTheme.accent, lineWidth: 1)
                    )
            }

            Button {
                withAnimation { isPresented = false }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(FolioTheme.muted)
            }
        }
        .padding()
    }
}

struct TypesetStep: Identifiable {
    let id = UUID()
    let latex: String
    let markdown: String
    let status: StepStatus?
}

struct MathJaxWebView: UIViewRepresentable {
    let steps: [TypesetStep]

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.isOpaque = false
        view.backgroundColor = .clear
        view.navigationDelegate = context.coordinator
        context.coordinator.steps = steps
        do {
            guard let asset = Bundle.main.url(forResource: "tex-svg", withExtension: "js") else { return view }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("InkPadMathJax", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let target = directory.appendingPathComponent("tex-svg.js")
            if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.copyItem(at: asset, to: target) }
            let html = directory.appendingPathComponent("preview.html")
            try Self.html.write(to: html, atomically: true, encoding: .utf8)
            view.loadFileURL(html, allowingReadAccessTo: directory)
        } catch { /* The adjacent SwiftUI raw LaTeX remains available. */ }
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.steps = steps
        context.coordinator.render(view)
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var steps: [TypesetStep] = []
        var ready = false
        var rendering = false
        var last: [String] = []
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true; render(webView) }
        func render(_ view: WKWebView) {
            let values = steps.map(\.latex)
            guard ready, !rendering, values != last else { return }
            rendering = true
            Task { @MainActor in
                do {
                    _ = try await view.callAsyncJavaScript("await window.renderRows(rows);", arguments: ["rows": values], in: nil, contentWorld: .page)
                    self.last = values
                } catch { /* Keep raw LaTeX visible beside the renderer. */ }
                self.rendering = false
                if self.steps.map(\.latex) != values { self.render(view) }
            }
        }
    }
    static let html = #"""
    <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
    <style>body{margin:8px;color:#1c1c1a;background:white;font-size:20px} .row{padding:8px;overflow-x:auto} </style>
    <script>window.MathJax={tex:{inlineMath:[['\\(','\\)']]},svg:{fontCache:'local'},options:{enableMenu:false},startup:{typeset:false}};</script>
    <script src="tex-svg.js"></script></head><body><div id="rows"></div>
    <script>window.renderRows=async function(rows){
      if(!window.MathJax || !MathJax.startup) throw new Error('MathJax unavailable');
      await MathJax.startup.promise;
      MathJax.typesetClear(); const host=document.getElementById('rows'); host.replaceChildren();
      rows.forEach(latex=>{const row=document.createElement('div');row.className='row';row.textContent='\\('+latex+'\\)';host.appendChild(row);});
      await MathJax.typesetPromise([host]);return true;
    };</script></body></html>
    """#
}
