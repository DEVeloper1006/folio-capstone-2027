import SwiftUI
import SwiftData
import PencilKit

struct NotebookView: View {
    @Environment(\.modelContext) private var modelContext
    let notebook: Notebook

    private var sortedPages: [Page] {
        notebook.pages.sorted { $0.sortIndex < $1.sortIndex }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(sortedPages) { page in
                    NavigationLink(value: page) {
                        PageThumbnail(page: page)
                    }
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            deletePage(page)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(notebook.name)
        .toolbar {
            Button {
                addPage()
            } label: {
                Label("Add Page", systemImage: "plus")
            }
        }
    }

    private func addPage() {
        let nextIndex = (sortedPages.last?.sortIndex ?? -1) + 1
        let page = Page(sortIndex: nextIndex)
        page.notebook = notebook
        notebook.pages.append(page)
    }

    private func deletePage(_ page: Page) {
        guard notebook.pages.count > 1 else { return }
        modelContext.delete(page)
    }
}

private struct PageThumbnail: View {
    let page: Page

    var body: some View {
        let drawing = page.drawingData.flatMap({ try? PKDrawing(data: $0) }) ?? PKDrawing()
        let bg = page.background

        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 4, y: 2)

            PageBackgroundView(style: bg, pageSize: CGSize(width: 300, height: 400))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            if let image = thumbnailImage(from: drawing) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
            }

            VStack {
                Spacer()
                HStack {
                    Text("Page \(page.sortIndex + 1)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(6)
                    Spacer()
                }
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .frame(maxWidth: 300)
    }

    private func thumbnailImage(from drawing: PKDrawing) -> UIImage? {
        guard !drawing.strokes.isEmpty else { return nil }
        let bounds = drawing.bounds
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        return drawing.image(from: bounds, scale: 1.0)
    }
}
