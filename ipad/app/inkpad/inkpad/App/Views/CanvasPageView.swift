import SwiftUI
import SwiftData
import PencilKit

struct CanvasPageView: View {
    @Environment(\.modelContext) private var modelContext
    let page: Page

    var body: some View {
        if let notebook = page.notebook {
            NotebookView(notebook: notebook)
        } else {
            Text("Page not associated with a notebook.")
                .foregroundStyle(FolioTheme.muted)
        }
    }
}
