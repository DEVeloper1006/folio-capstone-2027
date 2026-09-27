import SwiftUI

struct AppNavigation: View {
    var body: some View {
        NavigationStack {
            LibraryView()
                .navigationDestination(for: Notebook.self) { notebook in
                    NotebookView(notebook: notebook)
                }
                .navigationDestination(for: Page.self) { page in
                    CanvasPageView(page: page)
                }
        }
    }
}
