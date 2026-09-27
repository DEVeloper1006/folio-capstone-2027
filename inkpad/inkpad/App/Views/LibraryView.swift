import SwiftUI
import SwiftData

enum LibraryTab: String, CaseIterable {
    case notebooks = "Notebooks"
    case classes = "Classes"
}

enum UserRole: String, CaseIterable {
    case student = "Student"
    case instructor = "Instructor"
}

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Notebook.createdAt, order: .reverse) private var notebooks: [Notebook]
    @State private var showNewNotebook = false
    @State private var newName = ""
    @State private var renamingNotebook: Notebook?
    @State private var renameText = ""
    @State private var selectedTab: LibraryTab = .notebooks
    @State private var userRole: UserRole = .student
    @State private var showSettings = false

    private let columns = [GridItem(.adaptive(minimum: 170), spacing: 24)]
    private let classService: ClassService = MockClassService()

    var body: some View {
        VStack(spacing: 0) {
            tabSelector
            if selectedTab == .notebooks {
                notebooksGrid
            } else {
                classesGrid
            }
        }
        .background(FolioTheme.paper)
        .navigationTitle("Folio")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    Button {
                        newName = ""
                        showNewNotebook = true
                    } label: {
                        Label("New Notebook", systemImage: "plus")
                    }
                }
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
        .sheet(isPresented: $showSettings) { settingsSheet }
        .onAppear {
            if notebooks.isEmpty { seedData() }
        }
    }

    private var tabSelector: some View {
        HStack(spacing: 0) {
            ForEach(LibraryTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation { selectedTab = tab }
                } label: {
                    Text(tab.rawValue)
                        .font(FolioTheme.uiFont(size: 14, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? FolioTheme.ink : FolioTheme.muted)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            selectedTab == tab ? FolioTheme.panelSecondary : Color.clear
                        )
                        .clipShape(Capsule())
                }
            }
        }
        .padding(4)
        .background(FolioTheme.panel.clipShape(Capsule()))
        .padding(.top, 8)
    }

    private var notebooksGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 24) {
                newNotebookTile
                ForEach(notebooks) { notebook in
                    NavigationLink(value: notebook) {
                        NotebookCard(notebook: notebook, isInstructor: userRole == .instructor)
                    }
                    .contextMenu {
                        Button("Rename") {
                            renameText = notebook.name
                            renamingNotebook = notebook
                        }
                        Button("Duplicate") { duplicateNotebook(notebook) }
                        if userRole == .instructor {
                            Button("Publish") { }
                        }
                        Button("Delete", role: .destructive) {
                            modelContext.delete(notebook)
                        }
                    }
                }
            }
            .padding(24)
        }
    }

    private var classesGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 24) {
                ForEach(classService.availableClasses()) { classInfo in
                    NavigationLink(value: classInfo.id) {
                        classCard(classInfo)
                    }
                }
            }
            .padding(24)
        }
    }

    private func classCard(_ info: ClassInfo) -> some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(FolioTheme.accent.opacity(0.15))
                    .shadow(color: FolioTheme.chromeShadow, radius: 4, y: 2)

                VStack(spacing: 6) {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(FolioTheme.accent)
                    Text(info.courseCode)
                        .font(FolioTheme.uiFont(size: 14, weight: .bold))
                        .foregroundStyle(FolioTheme.ink)
                    Text(info.name)
                        .font(FolioTheme.uiFont(size: 12))
                        .foregroundStyle(FolioTheme.muted)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .aspectRatio(3.0 / 4.0, contentMode: .fit)

            VStack(spacing: 2) {
                Text(info.courseCode)
                    .font(FolioTheme.uiFont(size: 13, weight: .medium))
                    .foregroundStyle(FolioTheme.ink)
                Text("\(info.exampleCount) examples")
                    .font(FolioTheme.uiFont(size: 11))
                    .foregroundStyle(FolioTheme.dim)
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

    private var settingsSheet: some View {
        NavigationStack {
            Form {
                Section("Role") {
                    Picker("Role", selection: $userRole) {
                        ForEach(UserRole.allCases, id: \.self) { role in
                            Text(role.rawValue).tag(role)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { showSettings = false }
                }
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
    var isInstructor: Bool = false

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
