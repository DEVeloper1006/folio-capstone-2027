import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Notebook.createdAt, order: .reverse) private var notebooks: [Notebook]
    @State private var showNewNotebook = false
    @State private var newName = ""
    @State private var renamingNotebook: Notebook?
    @State private var renameText = ""

    private let columns = [GridItem(.adaptive(minimum: 170), spacing: 24)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 24) {
                newNotebookTile
                ForEach(notebooks) { notebook in
                    NavigationLink(value: notebook) {
                        NotebookCard(notebook: notebook)
                    }
                    .contextMenu {
                        Button("Rename") {
                            renameText = notebook.name
                            renamingNotebook = notebook
                        }
                        Button("Duplicate") {
                            duplicateNotebook(notebook)
                        }
                        Button("Delete", role: .destructive) {
                            modelContext.delete(notebook)
                        }
                    }
                }
            }
            .padding(24)
        }
        .background(FolioTheme.paper)
        .navigationTitle("Folio")
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
        .onAppear {
            if notebooks.isEmpty {
                seedData()
            }
        }
    }

    private var newNotebookTile: some View {
        Button {
            newName = ""
            showNewNotebook = true
        } label: {
            VStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(FolioTheme.rule, style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 28, weight: .light))
                            Text("New notebook")
                                .font(FolioTheme.uiFont(size: 13))
                        }
                        .foregroundStyle(FolioTheme.muted)
                    )
                Color.clear.frame(height: 32)
            }
        }
    }

    private func createNotebook() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let colorIndex = notebooks.count % FolioTheme.coverColors.count
        let notebook = Notebook(name: name, coverColorIndex: colorIndex)
        let firstPage = Page(sortIndex: 0)
        firstPage.notebook = notebook
        notebook.pages.append(firstPage)
        modelContext.insert(notebook)
    }

    private func duplicateNotebook(_ notebook: Notebook) {
        let copy = Notebook(name: notebook.name + " copy", mathMode: notebook.mathMode, coverColorIndex: (notebook.coverColorIndex + 1) % FolioTheme.coverColors.count)
        let page = Page(sortIndex: 0)
        page.notebook = copy
        copy.pages.append(page)
        modelContext.insert(copy)
    }

    private func seedData() {
        SeedDataBuilder.seed(into: modelContext)
    }
}

private struct NotebookCard: View {
    let notebook: Notebook

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(FolioTheme.coverColors[notebook.coverColorIndex % FolioTheme.coverColors.count])
                    .shadow(color: FolioTheme.chromeShadow, radius: 4, y: 2)

                VStack(spacing: 4) {
                    Text(notebook.name)
                        .font(FolioTheme.uiFont(size: 15, weight: .semibold))
                        .foregroundStyle(FolioTheme.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Text(notebook.mathMode.label)
                        .font(FolioTheme.uiFont(size: 10, weight: .bold))
                        .foregroundStyle(FolioTheme.paper)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(FolioTheme.ink.opacity(0.7)))
                }
                .padding()
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)

            VStack(spacing: 2) {
                Text(notebook.name)
                    .font(FolioTheme.uiFont(size: 13, weight: .medium))
                    .foregroundStyle(FolioTheme.ink)
                    .lineLimit(1)
                Text(notebook.lastEditedAt, style: .relative)
                    .font(FolioTheme.uiFont(size: 11))
                    .foregroundStyle(FolioTheme.dim)
            }
        }
    }
}
