import SwiftUI
import WebKit

struct MathRendererView: UIViewRepresentable {
    let html: String
    var minHeight: CGFloat = 40

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        loadContent(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        loadContent(in: webView)
    }

    private func loadContent(in webView: WKWebView) {
        let fullHTML = MathRenderer.wrapHTML(html)
        if let texSvgURL = Bundle.main.url(forResource: "tex-svg", withExtension: "js") {
            webView.loadHTMLString(fullHTML, baseURL: texSvgURL.deletingLastPathComponent())
        } else {
            webView.loadHTMLString(fullHTML, baseURL: nil)
        }
    }
}

enum MathRenderer {
    static func wrapHTML(_ bodyContent: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            body { font-family: Georgia, serif; padding: 8px; margin: 0;
                   background: transparent; color: #1C1C1A; font-size: 15px; line-height: 1.5; }
            .math-inline { display: inline; }
            .math-block { display: block; text-align: center; margin: 8px 0; overflow-x: auto; }
            mjx-container { overflow-x: auto; }
            .ai-text { color: #4E9A95; }
        </style>
        <script>
        window.MathJax = {
            tex: { inlineMath: [['$','$']], displayMath: [['$$','$$']] },
            svg: { fontCache: 'local' },
            startup: { typeset: true }
        };
        </script>
        <script src="tex-svg.js"></script>
        </head>
        <body>\(bodyContent)</body>
        </html>
        """
    }

    static func renderChatMessage(_ text: String, isAI: Bool) -> String {
        let escapedText = text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")

        var html = escapedText
        let lines = html.components(separatedBy: "\n")
        html = lines.map { line in
            if line.hasPrefix("$$") && line.hasSuffix("$$") {
                return "<div class=\"math-block\">\(line)</div>"
            }
            return "<p>\(line)</p>"
        }.joined()

        if isAI {
            html = "<div class=\"ai-text\">\(html)</div>"
        }
        return html
    }

    static func renderSteps(_ steps: [(latex: String, statusColor: String)]) -> String {
        steps.map { step in
            """
            <div style="display:flex;align-items:baseline;gap:8px;margin-bottom:16px;font-size:16px">
                <span style="color:\(step.statusColor);font-size:12px">●</span>
                <span>\\(\(step.latex)\\)</span>
            </div>
            """
        }.joined()
    }

    static func renderFormulaSheet(_ formulas: [(label: String, latex: String)]) -> String {
        formulas.map { f in
            """
            <div style="margin-bottom:12px">
                <div style="font-size:12px;color:#65625D;margin-bottom:2px">\(f.label)</div>
                <div>\\(\(f.latex)\\)</div>
            </div>
            """
        }.joined()
    }
}
