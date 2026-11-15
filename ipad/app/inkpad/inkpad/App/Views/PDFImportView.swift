import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PDFKit

struct PDFImportView: View {
    @Environment(\.modelContext) private var modelContext
    @Binding var isPresented: Bool
    let notebook: Notebook
    @State private var showFilePicker = false

    var body: some View {
        Button {
            showFilePicker = true
        } label: {
            Label("Import PDF", systemImage: "doc.fill")
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: false
        ) { result in
            handleImport(result)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        guard url.startAccessingSecurityScopedResource() else { return }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url),
              let document = PDFDocument(data: data) else { return }

        let pageCount = document.pageCount
        let existingCount = notebook.pages.count

        for i in 0..<pageCount {
            let page = Page(sortIndex: existingCount + i, backgroundStyle: .blank, mathMode: notebook.mathMode)
            page.drawingData = data
            page.notebook = notebook
            notebook.pages.append(page)
        }

        isPresented = false
    }
}
