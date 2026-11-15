import SwiftUI
import PencilKit

@MainActor @Observable
final class StrokeLabSession {
    nonisolated deinit {}
    var document = StrokeLabDocument()
    var canvas = PKCanvasView()
    var selection = Set<String>()
    var selectedGroups = Set<String>()
    var activeGroup: String?
    var author = "local-annotator"
    var label = "Expression"
    var rowLabel = "Visual row"
    var parentRowID: String?
    var error: String?
    var status = "New local page"
    var pages: [URL] = []
    var erasing = false
    var fingerDrawing = false
    var inspecting = false
    var dirty = false
    @ObservationIgnored private var autosaveTask: Task<Void, Never>?

    func perform(_ action: () throws -> Void) {
        do { try action() } catch { self.error = error.localizedDescription }
    }
    func refresh() { perform { pages = try StrokeLabStore().pages() } }
    func changed(_ drawing: PKDrawing) {
        dirty = true
        perform {
            try update(drawing)
            scheduleAutosave()
        }
    }
    private func update(_ drawing: PKDrawing) throws {
        let raw = try LabExport.page(from: drawing, preserving: document.raw)
        var annotations = document.annotations
        annotations.reconcile(existing: Set(raw.strokes.map(\.id)), author: effectiveAuthor)
        try LabValidation.validate(raw: raw, annotations: annotations)
        document.drawing = drawing
        document.raw = raw
        document.annotations = annotations
        selection.formIntersection(raw.strokes.map(\.id))
        dirty = true
    }
    var effectiveAuthor: String { author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "local-annotator" : author }
    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            guard !Task.isCancelled, let self else { return }
            self.save()
        }
    }
    var unassignedIDs: Set<String> {
        Set(document.raw.strokes.map(\.id)).subtracting(document.annotations.groups.flatMap(\.strokeIDs))
    }
    func save() {
        autosaveTask?.cancel()
        perform {
            try update(canvas.drawing)
            try StrokeLabStore().save(document)
            dirty = false
            status = "Saved locally"
            refresh()
        }
    }
    func open(_ url: URL) {
        autosaveTask?.cancel()
        perform {
            if dirty {
                try update(canvas.drawing)
                try StrokeLabStore().save(document)
            }
            let loaded = try StrokeLabStore().open(url)
            document = loaded
            canvas.drawing = loaded.drawing
            canvas.undoManager?.removeAllActions()
            selection = []; selectedGroups = []; activeGroup = nil; parentRowID = nil
            dirty = false
            status = "Opened \(loaded.raw.pageID.prefix(8))"
        }
    }
    func newPage() {
        autosaveTask?.cancel()
        perform {
            if dirty {
                try update(canvas.drawing)
                try StrokeLabStore().save(document)
            }
            document = StrokeLabDocument()
            canvas.drawing = document.drawing
            canvas.undoManager?.removeAllActions()
            selection = []; selectedGroups = []; activeGroup = nil; parentRowID = nil
            dirty = false
            status = "New local page"
            refresh()
        }
    }
    func annotate(_ action: (inout LabAnnotations) throws -> Void) {
        perform {
            var candidate = document.annotations
            try action(&candidate)
            try LabValidation.validate(raw: document.raw, annotations: candidate)
            document.annotations = candidate
            dirty = true
            scheduleAutosave()
        }
    }
    func createGroup() {
        let group = LabGroup(label: label, strokeIDs: [])
        annotate {
            $0.groups.append(group)
            $0.assign(selection, to: group.id, author: effectiveAuthor)
        }
        activeGroup = group.id
        parentRowID = nil
    }
    func addRow() {
        guard let groupID = activeGroup else { return }
        annotate { annotations in
            guard let index = annotations.groups.firstIndex(where: { $0.id == groupID }), !selection.isEmpty else { throw LabError.invalid("Select strokes in the active expression") }
            annotations.groups[index].rows.append(LabRow(label: rowLabel, parentRowID: parentRowID, strokeIDs: selection.sorted()))
            annotations.record("Add visual row", author: effectiveAuthor)
        }
    }
}

struct StrokeLabView: View {
    @State private var session = StrokeLabSession()
    @State private var exporting = false
    @Environment(\.scenePhase) private var scenePhase
    private let colors: [Color] = [.blue, .orange, .purple, .green, .pink, .cyan]

    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Stroke Lab").font(.title2.bold())
                    Text(session.status + (session.dirty ? " • Unsaved" : "")).font(.caption)
                    Text("Page: \(session.document.raw.pageID)").font(.caption2).textSelection(.enabled)
                    Text("\(session.document.raw.strokes.count) strokes · \(session.document.annotations.groups.count) expressions · \(session.selection.count) selected").font(.caption)
                    Text("Saves locally after a pause. Use Export for a copy in Files or on your Mac.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("New", action: session.newPage)
                        Button("Save", action: session.save)
                        Button("Export") {
                            session.save()
                            if session.error == nil { exporting = true }
                        }
                    }
                    Menu("Reopen local page") {
                        ForEach(session.pages, id: \.self) { url in
                            Button(String(url.deletingPathExtension().lastPathComponent.prefix(8))) { session.open(url) }
                        }
                    }
                    TextField("Annotator", text: $session.author).textFieldStyle(.roundedBorder)
                    Toggle("Finger drawing", isOn: $session.fingerDrawing)
                    Toggle("Whole-stroke eraser", isOn: $session.erasing)
                    Toggle("Show stroke bounds", isOn: $session.inspecting)
                    HStack {
                        Button("Undo ink") { session.canvas.undoManager?.undo() }
                        Button("Redo ink") { session.canvas.undoManager?.redo() }
                    }
                    Divider()
                    TextField("Expression label", text: $session.label).textFieldStyle(.roundedBorder)
                    Button("Create expression from selection", action: session.createGroup)
                        .disabled(session.selection.isEmpty)
                    ForEach(Array(session.document.annotations.groups.enumerated()), id: \.element.id) { index, group in
                        HStack {
                            Toggle(isOn: Binding(get: { session.selectedGroups.contains(group.id) }, set: { value in
                                if value { session.selectedGroups.insert(group.id) } else { session.selectedGroups.remove(group.id) }
                            })) { EmptyView() }.labelsHidden().toggleStyle(.checkboxCompatible)
                            Button {
                                session.activeGroup = group.id
                                session.parentRowID = nil
                            } label: {
                                Text("\(group.label) (\(group.strokeIDs.count)) \(session.activeGroup == group.id ? "•" : "")")
                                    .foregroundStyle(colors[index % colors.count])
                            }
                        }
                    }
                    Button("Assign selection to active expression") {
                        session.annotate { $0.assign(session.selection, to: session.activeGroup, author: session.effectiveAuthor) }
                    }.disabled(session.activeGroup == nil || session.selection.isEmpty)
                    Button("Make selection unassigned") {
                        session.annotate { $0.assign(session.selection, to: nil, author: session.effectiveAuthor) }
                    }.disabled(session.selection.isEmpty)
                    Button("Split selection from active expression") {
                        guard let id = session.activeGroup else { return }
                        session.annotate { try $0.split(session.selection, from: id, author: session.effectiveAuthor) }
                    }.disabled(session.activeGroup == nil)
                    Button("Merge checked expressions") {
                        session.annotate { try $0.merge(session.selectedGroups, author: session.effectiveAuthor) }
                        session.selectedGroups = []
                        session.activeGroup = nil; session.parentRowID = nil
                    }.disabled(session.selectedGroups.count < 2)
                    TextField("Visual row label", text: $session.rowLabel).textFieldStyle(.roundedBorder)
                    if let group = session.document.annotations.groups.first(where: { $0.id == session.activeGroup }) {
                        Picker("Parent row", selection: $session.parentRowID) {
                            Text("Top level").tag(String?.none)
                            ForEach(group.rows) { row in Text(row.label).tag(Optional(row.id)) }
                        }
                        Button("Add row from selected strokes", action: session.addRow)
                        ForEach(group.rows) { row in
                            HStack {
                                Text("\(row.parentRowID == nil ? "" : "↳ ")\(row.label): \(row.strokeIDs.count)").font(.caption)
                                Button("Remove") {
                                    session.annotate { annotations in
                                        guard let i = annotations.groups.firstIndex(where: { $0.id == group.id }) else { return }
                                        annotations.groups[i].rows.removeAll { $0.id == row.id }
                                        for j in annotations.groups[i].rows.indices where annotations.groups[i].rows[j].parentRowID == row.id {
                                            annotations.groups[i].rows[j].parentRowID = row.parentRowID
                                        }
                                        annotations.record("Remove visual row", author: session.effectiveAuthor)
                                    }
                                    session.parentRowID = nil
                                }
                            }
                        }
                    }
                    Divider()
                    Text("Select strokes below; bounds use matching colors. Unassigned: \(unassignedCount)").font(.caption)
                    Button("Select unassigned strokes") { session.selection = session.unassignedIDs }
                        .disabled(session.unassignedIDs.isEmpty)
                    Text("Write one equation, select its unassigned strokes, then create its expression group before writing the next.").font(.caption).foregroundStyle(.secondary)
                    Button("Clear selection") { session.selection = [] }
                    ForEach(Array(session.document.raw.strokes.enumerated()), id: \.element.id) { index, stroke in
                        Button {
                            if session.selection.contains(stroke.id) { session.selection.remove(stroke.id) } else { session.selection.insert(stroke.id) }
                        } label: {
                            VStack(alignment: .leading) {
                                Text("\(session.selection.contains(stroke.id) ? "☑" : "☐") Stroke \(index + 1) · \(stroke.id.suffix(6))")
                                Text("\(stroke.points.count) points · \(stroke.points.last?.time ?? 0, specifier: "%.3f") s").font(.caption)
                                if session.selection.contains(stroke.id) {
                                    Text("Bounds: \(stroke.bounds.x, specifier: "%.1f"), \(stroke.bounds.y, specifier: "%.1f") · \(stroke.bounds.width, specifier: "%.1f") × \(stroke.bounds.height, specifier: "%.1f") pt").font(.caption2)
                                    Text("Created: \(stroke.createdAt, specifier: "%.3f") Unix seconds").font(.caption2)
                                    Text("\(stroke.ink.type) · First pressure: \(stroke.points.first?.pressure ?? 0, specifier: "%.3f")").font(.caption2)
                                }
                            }
                        }
                    }
                }.padding()
            }.frame(width: 320)
            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    LabCanvas(session: session)
                    ForEach(Array(session.document.annotations.groups.enumerated()), id: \.element.id) { index, group in
                        if let bounds = groupBounds(group.strokeIDs) {
                            boundary(bounds, color: colors[index % colors.count], width: 2)
                        }
                    }
                    ForEach(session.document.raw.strokes) { stroke in
                        if session.inspecting || session.selection.contains(stroke.id) {
                            boundary(CGRect(x: stroke.bounds.x, y: stroke.bounds.y, width: stroke.bounds.width, height: stroke.bounds.height), color: session.selection.contains(stroke.id) ? .red : .gray, width: 1)
                        }
                    }
                }
                .frame(width: session.document.raw.canvasWidth, height: session.document.raw.canvasHeight)
                .background(.white)
            }.background(Color.gray.opacity(0.15))
        }
        .navigationTitle("Stroke Lab")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { session.refresh() }
        .onDisappear { if session.dirty { session.save() } }
        .onChange(of: scenePhase) { _, phase in if phase != .active && session.dirty { session.save() } }
        .alert("Stroke Lab", isPresented: Binding(get: { session.error != nil }, set: { if !$0 { session.error = nil } })) {
            Button("OK") { session.error = nil }
        } message: { Text(session.error ?? "") }
        .fileExporter(isPresented: $exporting, document: session.document, contentType: .folioInk,
                      defaultFilename: session.document.raw.pageID) { result in
            if case .failure(let error) = result { session.error = error.localizedDescription }
        }
    }

    private var unassignedCount: Int {
        session.unassignedIDs.count
    }
    private func groupBounds(_ ids: [String]) -> CGRect? {
        let rectangles = session.document.raw.strokes.filter { ids.contains($0.id) }.map {
            CGRect(x: $0.bounds.x, y: $0.bounds.y, width: $0.bounds.width, height: $0.bounds.height)
        }
        return rectangles.reduce(nil) { result, rect in result.map { $0.union(rect) } ?? rect }
    }
    private func boundary(_ rect: CGRect, color: Color, width: CGFloat) -> some View {
        Rectangle().stroke(color, lineWidth: width)
            .frame(width: max(1, rect.width), height: max(1, rect.height))
            .offset(x: rect.minX, y: rect.minY).allowsHitTesting(false)
    }
}

private struct LabCanvas: UIViewRepresentable {
    let session: StrokeLabSession
    func makeCoordinator() -> Coordinator { Coordinator(session) }
    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = session.canvas
        canvas.delegate = context.coordinator
        canvas.backgroundColor = .white
        canvas.isScrollEnabled = false
        canvas.drawing = session.document.drawing
        canvas.becomeFirstResponder()
        return canvas
    }
    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        canvas.drawingPolicy = session.fingerDrawing ? .anyInput : .pencilOnly
        canvas.tool = session.erasing ? PKEraserTool(.vector) : PKInkingTool(.pen, color: .black, width: 2)
    }
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let session: StrokeLabSession
        init(_ session: StrokeLabSession) { self.session = session }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) { session.changed(canvasView.drawing) }
    }
}

// A compact checkbox presentation supported on iPadOS.
private struct LabCheckboxStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            Image(systemName: configuration.isOn ? "checkmark.square" : "square")
        }.accessibilityLabel("Select expression for merging")
    }
}
private extension ToggleStyle where Self == LabCheckboxStyle {
    static var checkboxCompatible: LabCheckboxStyle { LabCheckboxStyle() }
}
