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

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        loadContent(in: webView)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        loadContent(in: webView)
    }

    private func loadContent(in webView: WKWebView) {
        let stepsHTML = steps.map { step in
            let statusColor: String
            switch step.status {
            case .unchecked: statusColor = "#8D8981"
            case .verified: statusColor = "#5A9E5A"
            case .warning: statusColor = "#C7943A"
            case .error: statusColor = "#C45C4A"
            case nil: statusColor = "#8D8981"
            }
            return """
            <div class="step">
                <span class="status" style="color:\(statusColor)">●</span>
                <span class="math">\\(\(step.latex)\\)</span>
            </div>
            """
        }.joined()

        let html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
            body { font-family: Georgia, serif; padding: 20px; margin: 0;
                   background: #FFFFFF; color: #1C1C1A; }
            .step { display: flex; align-items: baseline; gap: 8px;
                    margin-bottom: 16px; font-size: 16px; }
            .status { font-size: 12px; }
            mjx-container { overflow-x: auto; }
        </style>
        <script>
        window.MathJax = {
            tex: { inlineMath: [['\\\\(','\\\\)']], displayMath: [['\\\\[','\\\\]']] },
            svg: { fontCache: 'local' },
            startup: { typeset: true }
        };
        </script>
        <script src="tex-svg.js"></script>
        </head>
        <body>\(stepsHTML)</body>
        </html>
        """

        if let texSvgURL = Bundle.main.url(forResource: "tex-svg", withExtension: "js") {
            let baseURL = texSvgURL.deletingLastPathComponent()
            webView.loadHTMLString(html, baseURL: baseURL)
        } else {
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
}
