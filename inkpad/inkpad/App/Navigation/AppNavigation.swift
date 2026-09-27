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
                .navigationDestination(for: String.self) { classId in
                    ClassSpaceView(classInfo: MockClassService().availableClasses().first { $0.id == classId } ?? ClassInfo(id: classId, name: classId, courseCode: classId, instructor: "Unknown", exampleCount: 0))
                }
        }
    }
}
