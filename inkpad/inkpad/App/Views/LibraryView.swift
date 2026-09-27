import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Notebook.createdAt, order: .reverse) private var notebooks: [Notebook]
    @State private var showNewNotebook = false
    @State private var newName = ""
    @State private var renamingNotebook: Notebook?
    @State private var renameText = ""

    private let columns = [GridItem(.adaptive(minimum: 160), spacing: 20)]

    var body: some View {
        ScrollView {
            if notebooks.isEmpty {
                ContentUnavailableView("No Notebooks", systemImage: "book.closed", description: Text("Tap + to create your first notebook."))
                    .padding(.top, 100)
            } else {
                LazyVGrid(columns: columns, spacing: 20) {
                    ForEach(notebooks) { notebook in
                        NavigationLink(value: notebook) {
                            NotebookCard(notebook: notebook)
                        }
                        .contextMenu {
                            Button("Rename") {
                                renameText = notebook.name
                                renamingNotebook = notebook
                            }
                            Button("Delete", role: .destructive) {
                                modelContext.delete(notebook)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .navigationTitle("InkPad")
        .toolbar {
            Button {
                newName = ""
                showNewNotebook = true
            } label: {
                Label("New Notebook", systemImage: "plus")
            }
        }
        .alert("New Notebook", isPresented: $showNewNotebook) {
            TextField("Name", text: $newName)
            Button("Create") { createNotebook() }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Notebook", isPresented: Binding(
            get: { renamingNotebook != nil },
            set: { if !$0 { renamingNotebook = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                renamingNotebook?.name = renameText
                renamingNotebook = nil
            }
            Button("Cancel", role: .cancel) { renamingNotebook = nil }
        }
    }

    private func createNotebook() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let notebook = Notebook(name: name)
        let firstPage = Page(sortIndex: 0)
        firstPage.notebook = notebook
        notebook.pages.append(firstPage)
        modelContext.insert(notebook)
    }
}

private struct NotebookCard: View {
    let notebook: Notebook

    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray5))
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay(
                    Image(systemName: "book.closed")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                )
            Text(notebook.name)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(.primary)
        }
    }
}
