import SwiftUI
import PencilKit
import ImageIO
import WebKit

struct HandwritingRecord: Codable, Sendable {
    let id: String
    let date: Date
    let source: String
    let strokeCount: Int
    let expectedLatex: String
    let image: ImagePreparationInfo
    let preprocessingSeconds: Double
    let modelPreparationSeconds: Double
    let buttonToDecodedSeconds: Double
    let recognition: LocalRecognition
}

struct SavedRecognition: Sendable {
    let record: HandwritingRecord
    let folder: URL
}

/// PNG processing and file IO stay off the UI thread; the model actor is shared
/// with the fixture tab so loading a second copy cannot double model memory.
actor HandwritingProcessor {
    let runtime: ModelRuntime
    init(runtime: ModelRuntime) { self.runtime = runtime }

    func process(png: Data, strokes: Data, strokeCount: Int, expected: String,
                 started: Double, source: String = "pencilkit") async throws -> SavedRecognition {
        try Task.checkCancellation()
        let preprocessingStart = ProcessInfo.processInfo.systemUptime
        guard let imageSource = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw ProbeError.invalid("Could not open the handwriting image")
        }
        let prepared = try ImagePreprocessor.prepare(image)
        let preprocessingSeconds = ProcessInfo.processInfo.systemUptime - preprocessingStart
        let loadStart = ProcessInfo.processInfo.systemUptime
        try await runtime.load()
        let modelPreparationSeconds = ProcessInfo.processInfo.systemUptime - loadStart
        let recognition = try await runtime.recognize(prepared.values)
        try Task.checkCancellation()
        let record = HandwritingRecord(id: UUID().uuidString, date: Date(), source: source,
            strokeCount: strokeCount, expectedLatex: expected, image: prepared.info,
            preprocessingSeconds: preprocessingSeconds, modelPreparationSeconds: modelPreparationSeconds,
            buttonToDecodedSeconds: ProcessInfo.processInfo.systemUptime - started, recognition: recognition)
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Handwriting", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let staging = root.appendingPathComponent(".pending-" + record.id, isDirectory: true)
        let destination = root.appendingPathComponent(record.id, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try png.write(to: staging.appendingPathComponent("input.png"), options: .atomic)
            try strokes.write(to: staging.appendingPathComponent("strokes.drawing"), options: .atomic)
            try prepared.values.withUnsafeBytes { try Data($0).write(to: staging.appendingPathComponent("input.f32"), options: .atomic) }
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(record).write(to: staging.appendingPathComponent("result.json"), options: .atomic)
            try Task.checkCancellation()
            try FileManager.default.moveItem(at: staging, to: destination)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
        return SavedRecognition(record: record, folder: destination)
    }
}

@MainActor
final class PencilViewModel: ObservableObject {
    @Published var drawing = PKDrawing()
    @Published var expectedLatex = ""
    @Published var result: SavedRecognition?
    @Published var busy = false
    @Published var status = "Write one expression, then tap Recognize."
    @Published var erase = false
    @Published var revision = 0
    @Published var previewRendered = false
    @Published var previewError: String?
    private let processor: HandwritingProcessor
    private var task: Task<Void, Never>?

    init(runtime: ModelRuntime) { processor = HandwritingProcessor(runtime: runtime) }

    func changed(_ value: PKDrawing) {
        drawing = value; revision += 1
        result = nil
        previewRendered = false; previewError = nil
        status = "Write one expression, then tap Recognize."
    }

    func clear() {
        task?.cancel(); revision += 1; drawing = PKDrawing(); result = nil
        status = "Canvas cleared. Saved examples remain in Files."
    }

    func recognize(source: String = "pencilkit") {
        guard !busy else { return }
        let started = ProcessInfo.processInfo.systemUptime
        let snapshot = drawing, requestRevision = revision, expected = expectedLatex
        guard !snapshot.strokes.isEmpty, !snapshot.bounds.isEmpty, !snapshot.bounds.isInfinite else {
            status = "Write an expression first."; return
        }
        let bounds = snapshot.bounds.insetBy(dx: -12, dy: -12).integral
        let scale = min(2, 2048 / max(bounds.width, bounds.height))
        let format = UIGraphicsImageRendererFormat(); format.opaque = true; format.scale = scale
        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(origin: .zero, size: bounds.size))
            snapshot.image(from: bounds, scale: scale).draw(in: CGRect(origin: .zero, size: bounds.size))
        }
        guard let png = image.pngData() else { status = "Could not capture the handwriting image."; return }
        busy = true; result = nil; previewRendered = false; previewError = nil
        status = "Recognizing on this iPad… The first run loads the model."
        let strokes = snapshot.dataRepresentation()
        task = Task {
            defer { busy = false }
            do {
                let value = try await processor.process(png: png, strokes: strokes, strokeCount: snapshot.strokes.count,
                                                        expected: expected, started: started, source: source)
                try Task.checkCancellation()
                guard revision == requestRevision else { return }
                result = value
                status = "Recognized locally. Example saved on this iPad."
                print("FOLIO_HANDWRITING_SAVED " + value.folder.lastPathComponent)
            } catch is CancellationError {
                if revision == requestRevision { status = "Recognition cancelled." }
            } catch {
                if revision == requestRevision { status = error.localizedDescription }
            }
        }
    }

    func cancel() { task?.cancel(); status = "Cancelling after the current model step…" }

    func rendered(latex: String, error: String?) {
        guard result?.record.recognition.latex == latex else { return }
        previewRendered = error == nil; previewError = error
    }

    /// Exercises the actual capture → PNG → native preprocessing → model → save
    /// path on-device without claiming that generated strokes are human input.
    func smokeTest() async {
        let points = [CGPoint(x: 30, y: 30), CGPoint(x: 100, y: 100)]
        let second = [CGPoint(x: 100, y: 30), CGPoint(x: 30, y: 100)]
        let strokes = [points, second].map { points in
            PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points.enumerated().map { index, point in
                PKStrokePoint(location: point, timeOffset: Double(index) * 0.2, size: CGSize(width: 3, height: 3),
                              opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }, creationDate: Date()))
        }
        drawing = PKDrawing(strokes: strokes)
        expectedLatex = "x"
        recognize(source: "generated-pencilkit-smoke")
        await task?.value
        // Let the real WKWebView typeset the result before declaring UI success.
        for _ in 0..<100 {
            if previewRendered || previewError != nil { break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        if let result, previewRendered {
            print("FOLIO_PENCIL_SMOKE " + result.folder.lastPathComponent)
            exit(0)
        }
        print("FOLIO_PENCIL_SMOKE_ERROR " + (previewError ?? status)); exit(3)
    }
}

struct PencilCanvas: UIViewRepresentable {
    let drawing: PKDrawing
    let erase: Bool
    let changed: (PKDrawing) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(changed: changed) }
    func makeUIView(context: Context) -> PKCanvasView {
        let view = PKCanvasView()
        view.delegate = context.coordinator; view.drawingPolicy = .anyInput
        view.backgroundColor = .white; view.isOpaque = true
        view.overrideUserInterfaceStyle = .light
        view.isScrollEnabled = false; view.drawing = drawing
        view.accessibilityIdentifier = "handwritingCanvas"
        return view
    }
    func updateUIView(_ view: PKCanvasView, context: Context) {
        context.coordinator.changed = changed
        if view.drawing.dataRepresentation() != drawing.dataRepresentation() {
            context.coordinator.updating = true
            view.drawing = drawing
            context.coordinator.updating = false
        }
        view.tool = erase ? PKEraserTool(.vector) : PKInkingTool(.pen, color: .black, width: 3)
    }
    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var changed: (PKDrawing) -> Void
        var updating = false
        init(changed: @escaping (PKDrawing) -> Void) { self.changed = changed }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            if !updating { changed(canvasView.drawing) }
        }
    }
}

struct PencilRecognitionView: View {
    @ObservedObject var model: PencilViewModel
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Write one expression. Recognition runs entirely on this iPad.")
                    HStack {
                        Button("Recognize") { model.recognize() }
                            .buttonStyle(.borderedProminent).disabled(model.busy || model.drawing.strokes.isEmpty)
                            .accessibilityIdentifier("recognizeHandwriting")
                        Button("Clear") { model.clear() }.disabled(model.busy)
                        Toggle("Eraser", isOn: $model.erase).toggleStyle(.button).disabled(model.busy)
                        if model.busy { ProgressView(); Button("Cancel") { model.cancel() } }
                    }
                    Text(model.status).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                    if geometry.size.width >= 760 {
                        HStack(alignment: .top, spacing: 20) {
                            canvas.frame(maxWidth: .infinity)
                            output.frame(width: max(280, geometry.size.width * 0.36))
                        }
                    } else { canvas; output }
                    TextField("Expected LaTeX (optional, for this saved example)", text: $model.expectedLatex)
                        .textFieldStyle(.roundedBorder).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .disabled(model.busy)
                    Text("Each recognition saves the drawing, input image, normalized tensor and result under Files → On My iPad → Folio ML Probe → Handwriting. Nothing is uploaded. The optional expected LaTeX is saved when you tap Recognize.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding()
            }
        }.navigationTitle("Write & Recognize")
    }

    private var canvas: some View {
        VStack(alignment: .leading) {
            Text("Handwriting").font(.headline)
            PencilCanvas(drawing: model.drawing, erase: model.erase, changed: model.changed)
                .frame(height: 390).allowsHitTesting(!model.busy)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.4)))
        }
    }

    private var output: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recognition").font(.headline)
            if let saved = model.result {
                let result = saved.record.recognition
                LocalLatexView(latex: result.latex, completed: model.rendered).frame(height: 140)
                if let error = model.previewError {
                    Text("Preview unavailable: " + error + ". Raw LaTeX is below.").font(.caption)
                }
                Text("LaTeX").font(.subheadline)
                Text(result.latex.isEmpty ? "(Empty output)" : result.latex)
                    .font(.system(.body, design: .monospaced)).textSelection(.enabled)
                    .accessibilityIdentifier("recognizedLatex")
                Button("Copy LaTeX") { UIPasteboard.general.string = result.latex }
                Text(String(format: "Capture → decoded: %.2f s\nPreprocessing: %.3f s\nModel preparation: %.2f s\nEncoder: %.2f s · Decoder: %.2f s",
                            saved.record.buttonToDecodedSeconds, saved.record.preprocessingSeconds,
                            saved.record.modelPreparationSeconds, result.encoderSeconds, result.decoderSeconds))
                    .font(.caption).monospacedDigit()
                Text("Check the expression before using it. Recognition can miss exponents and symbols.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Your typeset expression and LaTeX will appear here.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 180)
            }
        }
    }
}

/// Bundled MathJax; LaTeX is passed as a structured JS argument and inserted as
/// text, never interpolated into HTML or executable script.
struct LocalLatexView: UIViewRepresentable {
    let latex: String
    let completed: (String, String?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView(); view.navigationDelegate = context.coordinator
        context.coordinator.latex = latex
        context.coordinator.completed = completed
        if let url = Bundle.main.url(forResource: "preview", withExtension: "html", subdirectory: "Fixtures") {
            view.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return view
    }
    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.completed = completed
        context.coordinator.latex = latex; context.coordinator.render(view)
    }
    final class Coordinator: NSObject, WKNavigationDelegate {
        var latex = "", ready = false, rendering = false
        var lastAttempt: String?
        var completed: ((String, String?) -> Void)?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { ready = true; render(webView) }
        func render(_ view: WKWebView) {
            guard ready, !rendering, lastAttempt != latex else { return }
            rendering = true; let current = latex; lastAttempt = current
            Task { @MainActor in
                do {
                    let value = try await view.callAsyncJavaScript("return await window.renderLatex(latex);", arguments: ["latex": current], in: nil, contentWorld: .page)
                    guard value as? Bool == true else { throw ProbeError.invalid("No typeset preview was produced") }
                    self.completed?(current, nil)
                    print("FOLIO_LATEX_RENDER_OK")
                } catch { self.completed?(current, error.localizedDescription) }
                self.rendering = false
                if self.latex != current { self.render(view) }
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(action.request.url?.isFileURL == true ? .allow : .cancel)
        }
    }
}
