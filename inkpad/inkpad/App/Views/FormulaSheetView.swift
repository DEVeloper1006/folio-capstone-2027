import SwiftUI

struct FormulaSheetView: View {
    let formulas: [(label: String, latex: String)]
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MathRendererView(
                    html: MathRenderer.renderFormulaSheet(formulas),
                    minHeight: 300
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(FolioTheme.chromeBackground)
            .navigationTitle("Formula Sheet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { isPresented = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            let latex = formulas.map { "% \($0.label)\n\\(\($0.latex)\\)" }.joined(separator: "\n\n")
                            UIPasteboard.general.string = latex
                        } label: {
                            Label("Copy LaTeX", systemImage: "doc.on.doc")
                        }
                        Button {
                            let md = formulas.map { "**\($0.label):** $\($0.latex)$" }.joined(separator: "\n\n")
                            UIPasteboard.general.string = md
                        } label: {
                            Label("Copy Markdown", systemImage: "text.document")
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
    }
}
