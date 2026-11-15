import SwiftUI
import PDFKit

struct PDFPageBackgroundView: UIViewRepresentable {
    let pdfData: Data
    let pageIndex: Int

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.isUserInteractionEnabled = false
        pdfView.backgroundColor = .clear
        loadPage(in: pdfView)
        return pdfView
    }

    func updateUIView(_ pdfView: PDFView, context: Context) {
        loadPage(in: pdfView)
    }

    private func loadPage(in pdfView: PDFView) {
        guard let document = PDFDocument(data: pdfData) else { return }
        pdfView.document = document
        if let page = document.page(at: pageIndex) {
            pdfView.go(to: page)
        }
    }
}
