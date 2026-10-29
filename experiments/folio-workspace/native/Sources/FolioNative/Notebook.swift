import SwiftUI
import FolioCore

@MainActor final class Notebook: ObservableObject {
    @Published var document = InkDocument(title: "Live notebook")
    @Published var regions: [ShadowRegion] = []
    @Published var selected: UUID?
    @Published var correction = ""
    @Published var status = "Local preview. Your ink stays yours."
    @Published var busy = false
    @Published var localStatus = "Local model connects after you write."
    @Published var localModel = "Local model: checking connection..."
    @Published var localDrafts: [UUID: LocalDraft] = [:]
    @Published var recognitionMode = "math"
    @Published private var failedRows: [UUID: [InkStroke]] = [:]
    private var ocrTask: Task<Void, Never>?
    @Published var cloudConsent = false
    @Published var endpoint = "http://127.0.0.1:8001"
    @Published var saveStatus = "Saved locally"
    private var revision = 0
    private var localTask: Task<Void, Never>?
    private var cloudTask: Task<Void, Never>?
    private var examples: [InkExample] = []
    private var undoStates: [InkDocument] = []
    private var redoStates: [InkDocument] = []
    private var writable = true
    private let file: URL
    private let localSession: URLSession
    private let writer = NotebookWriter()
    private var saveGeneration = 0

    init(storageURL: URL? = nil, localSession: URLSession = .shared) {
        self.localSession = localSession
        let directory = storageURL?.deletingLastPathComponent() ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("FolioShadow", isDirectory: true)
        file = storageURL ?? directory.appendingPathComponent("notebook.json")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: file.path) { document = try InkDocument.decode(Data(contentsOf: file)) }
        } catch {
            writable = false
            saveStatus = "Could not open notebook. Original file preserved."
        }
        refresh()
    }
    var selection: ShadowRegion? { regions.first { $0.id == selected } }
    var canUndo: Bool { !undoStates.isEmpty }
    var canRedo: Bool { !redoStates.isEmpty }

    func change(strokes: [InkStroke], pencilData: Data? = nil) {
        guard strokes != document.strokes || pencilData != document.pencilKitData else { return }
        var candidate = document
        candidate.strokes = strokes; candidate.pencilKitData = pencilData
        do { _ = try candidate.validated() } catch { status = "Page limit reached. Undo the last stroke or start a new page."; return }
        checkpoint()
        document = candidate
        changed()
    }
    func clearPage() {
        checkpoint()
        document = InkDocument(title: document.title)
        failedRows.removeAll()
        changed()
    }
    private func checkpoint() {
        undoStates.append(document)
        if undoStates.count > 30 { undoStates.removeFirst() }
        redoStates.removeAll()
    }
    func undo() {
        guard let old = undoStates.popLast() else { return }
        redoStates.append(document); document = old; changed()
    }
    func redo() {
        guard let next = redoStates.popLast() else { return }
        undoStates.append(document); document = next; changed()
    }
    private func changed() {
        revision += 1; document.updatedAt = Date()
        cloudTask?.cancel(); busy = false
        selected = nil; correction = ""
        save(); refresh()
    }
    private func save() {
        guard writable else { return }
        saveGeneration += 1
        let generation = saveGeneration, snapshot = document, url = file
        saveStatus = "Saving..."
        Task {
            do {
                try await writer.write(snapshot, to: url, generation: generation)
                if generation == saveGeneration { saveStatus = "Saved locally" }
            } catch {
                if generation == saveGeneration { saveStatus = "Save failed. Keep this window open and retry." }
            }
        }
    }
    func retrySave() { save() }
    private func refresh(invalidateCache: Bool = false) {
        localTask?.cancel()
        let strokes = document.strokes, examples = examples, version = revision
        let previous = invalidateCache ? [] : regions
        localTask = Task {
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) { ShadowRecognizer(examples: examples).regions(strokes, previous: previous) }.value
            guard !Task.isCancelled, version == revision else { return }
            regions = result
            localDrafts = localDrafts.filter { key, value in result.contains { $0.id == key && $0.strokes == value.strokes } }
            startLocalRecognition()
        }
    }
    func select(_ region: ShadowRegion) {
        cloudTask?.cancel(); busy = false
        selected = region.id
        correction = document.expressions.last(where: { $0.sourceStrokes == region.strokes })?.latex ?? localDraft(region)?.latex ?? region.node.latex ?? ""
        status = "Draft only. Correct the LaTeX, then accept."
    }
    func accepted(_ region: ShadowRegion) -> AcceptedExpression? {
        document.expressions.last { $0.sourceStrokes == region.strokes }
    }
    func accept() {
        guard let region = selection, !correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, correction.count <= 10000 else { return }
        checkpoint()
        document.expressions.removeAll { $0.sourceStrokes == region.strokes }
        document.expressions.append(AcceptedExpression(latex: correction, provider: "user-reviewed", sourceStrokes: region.strokes))
        // Acceptance invalidates outstanding requests without changing the ink.
        revision += 1; cloudTask?.cancel(); busy = false
        document.updatedAt = Date(); save()
        status = "Accepted. Original ink preserved."
    }
    func learnSymbol() {
        guard let region = selection, correction.count == 1, correction.first?.isLetter == true || correction.first?.isNumber == true else {
            status = "Teach one letter or digit at a time, on its own row."; return
        }
        examples.append(InkExample(latex: correction, strokes: region.strokes))
        if examples.count > 32 { examples.removeFirst() }
        refresh(invalidateCache: true); status = "Example learned for this session. Similar shapes remain drafts."
    }
    func correctionChanged() {
        cloudTask?.cancel(); busy = false
    }
    func revokeCloud() { cloudTask?.cancel(); busy = false }

    struct LocalDraft {
        let strokes: [InkStroke]
        let latex: String
        let seconds: Double
        let alternatives: [String]
    }
    func localDraft(_ region: ShadowRegion) -> LocalDraft? {
        guard let draft = localDrafts[region.id], draft.strokes == region.strokes else { return nil }
        return draft
    }
    func localFailed(_ region: ShadowRegion) -> Bool { failedRows[region.id] == region.strokes }
    func useLocalDraft() {
        if let region = selection, let draft = localDraft(region) { correction = draft.latex }
    }
    func changeRecognitionMode() {
        cloudTask?.cancel(); busy = false
        revision += 1
        localDrafts.removeAll()
        failedRows.removeAll()
        localStatus = recognitionMode == "numbers" ? "Numbers mode: numeric readings only." : "Algebra mode: numbers and variables."
        refresh()
    }
    func refreshLocalModel() async {
        do {
            var request = URLRequest(url: URL(string: "http://127.0.0.1:8002/health")!)
            request.timeoutInterval = 3
            let (data, response) = try await localSession.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            struct Health: Decodable { let ready: Bool; let profile: String? }
            let health = try JSONDecoder().decode(Health.self, from: data)
            guard health.ready else { throw URLError(.cannotConnectToHost) }
            updateLocalModel(health.profile)
        } catch { localModel = "Local model unavailable" }
    }
    private func updateLocalModel(_ profile: String?) {
        localModel = profile == "grade12" ? "TexTeller + Grade 12 adapter (local)" : "TexTeller original (local)"
    }
    func retryLocalRecognition() {
        failedRows.removeAll(); startLocalRecognition()
        Task { await refreshLocalModel() }
    }
    func startLocalRecognition() {
        guard ocrTask == nil else { return }
        ocrTask = Task {
            defer { ocrTask = nil }
            // One in-flight request. Edits coalesce while the model works.
            // Do not cancel inference on every pen stroke or queue old snapshots.
            var busyRetries = 0
            while !Task.isCancelled {
                let version = revision, mode = recognitionMode
                try? await Task.sleep(for: .milliseconds(650))
                guard !Task.isCancelled else { return }
                if revision != version { continue }
                guard let region = regions.last(where: { localDraft($0) == nil && accepted($0) == nil && failedRows[$0.id] != $0.strokes }),
                      document.strokes.filter({ s in region.strokes.contains(where: { $0.id == s.id }) }).count == region.strokes.count,
                      let image = inkPNG(region.strokes) else { return }
                localStatus = "Reading handwriting on this Mac..."
                do {
                    var request = URLRequest(url: URL(string: "http://127.0.0.1:8002/recognize")!)
                    request.httpMethod = "POST"; request.timeoutInterval = 90
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONEncoder().encode(["image": "data:image/png;base64," + image.base64EncodedString(), "mode": mode])
                    let (data, response) = try await localSession.data(for: request)
                    guard revision == version, recognitionMode == mode else { continue }
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                        if (response as? HTTPURLResponse)?.statusCode == 503 && busyRetries < 3 {
                            busyRetries += 1
                            localStatus = "Local model is busy. Retrying..."
                            try await Task.sleep(for: .seconds(1))
                            continue
                        }
                        if (response as? HTTPURLResponse)?.statusCode == 422 {
                            failedRows[region.id] = region.strokes
                            localStatus = mode == "numbers" ? "A row has no numeric reading. Switch to Algebra for variables, or correct it manually." : "A row could not be read. Its ink is preserved."
                            continue
                        }
                        localStatus = "Local recognition is busy or unavailable. Try Retry local."; return
                    }
                    struct Reply: Decodable { let latex: String; let seconds: Double; let alternatives: [String]?; let profile: String? }
                    let reply = try JSONDecoder().decode(Reply.self, from: data)
                    updateLocalModel(reply.profile)
                    busyRetries = 0
                    // Compare actual current ink, not the preview's older snapshot.
                    let current = document.strokes.filter { s in region.strokes.contains { $0.id == s.id } }.sorted { $0.id.uuidString < $1.id.uuidString }
                    if revision == version && current == region.strokes && !reply.latex.isEmpty && reply.latex.count <= 10000 {
                        localDrafts[region.id] = LocalDraft(strokes: region.strokes, latex: reply.latex, seconds: reply.seconds, alternatives: reply.alternatives ?? [])
                        localStatus = String(format: "Local draft ready in %.1f s. Review before accepting.", reply.seconds)
                    }
                } catch {
                    if revision != version || recognitionMode != mode { continue }
                    localStatus = "Local model is not reachable. Run ./scripts/start-local-ocr, then Retry local."; return
                }
            }
        }
    }

    func resolve(image: Data) {
        guard cloudConsent, let region = selection, accepted(region) == nil else { return }
        guard let base = URL(string: endpoint), base.scheme == "https" || (base.scheme == "http" && ["localhost", "127.0.0.1"].contains(base.host ?? "")) else {
            status = "Use HTTPS for a remote server, or HTTP on localhost."; return
        }
        guard image.count < 2_500_000 else { status = "Region is too large. Select a smaller row."; return }
        cloudTask?.cancel()
        let ticket = RecognitionTicket(documentID: document.id, revision: revision, strokes: region.strokes)
        let regionID = region.id
        busy = true; status = "Reading this row. Keep writing."
        cloudTask = Task {
            defer { if selected == regionID && revision == ticket.revision { busy = false } }
            do {
                var request = URLRequest(url: base.appendingPathComponent("api/recognize"))
                request.httpMethod = "POST"; request.timeoutInterval = 50
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(["image": "data:image/png;base64," + image.base64EncodedString()])
                let (data, response) = try await URLSession.shared.data(for: request)
                try Task.checkCancellation()
                guard selected == regionID, let current = selection,
                      ticket.matches(documentID: document.id, revision: revision, strokes: current.strokes) else { return }
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    status = "Cloud recognition unavailable. Ink is safe; retry or correct locally."; return
                }
                struct Reply: Decodable { let latex: String; let note: String }
                let reply = try JSONDecoder().decode(Reply.self, from: data)
                guard !reply.latex.isEmpty, reply.latex.count <= 10000 else { status = "No readable expression returned."; return }
                correction = reply.latex
                status = reply.note.isEmpty ? "Cloud draft ready. Review before accepting." : String(reply.note.prefix(300))
            } catch {
                if !Task.isCancelled { status = "Could not reach recognition server. Ink is safe; retry when connected." }
            }
        }
    }
}
