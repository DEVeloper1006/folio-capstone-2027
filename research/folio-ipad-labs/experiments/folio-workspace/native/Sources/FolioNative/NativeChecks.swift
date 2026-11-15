#if os(macOS)
import AppKit
import WebKit
import SwiftUI
import FolioCore

@MainActor enum NativeChecks {
    struct Failure: Error { let message: String }
    static func require(_ value: Bool, _ message: String) throws {
        if !value { throw Failure(message: message) }
    }
    static func wait(_ description: String, until condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw Failure(message: "Timed out: \(description)")
    }
    static func run() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("folio-check-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("notebook.json")
        let book = Notebook(storageURL: file)
        await book.refreshLocalModel()
        let profile = ProcessInfo.processInfo.environment["FOLIO_OCR_PROFILE"] ?? "grade12"
        let expectedModel = profile == "grade12" ? "TexTeller + Grade 12 adapter (local)" : "TexTeller original (local)"
        try require(book.localModel == expectedModel, "App connected to an unexpected model profile")
        // Stroke fixture, not text rendered into an image: 2 + 2 = 4.
        let two: [[Double]] = [[0,10],[8,2],[18,0],[28,5],[30,13],[25,23],[0,44],[31,44]]
        func stroke(_ points: [[Double]], x: Double, y: Double = 60) -> InkStroke {
            InkStroke(points: points.map { InkPoint(x: $0[0]+x, y: $0[1]+y) })
        }
        let strokes = [stroke(two,x:30), stroke([[0,22],[30,22]],x:85), stroke([[15,7],[15,37]],x:85),
                       stroke(two,x:140), stroke([[0,15],[30,15]],x:195), stroke([[0,29],[30,29]],x:195),
                       stroke([[24,0],[0,30],[32,30]],x:250), stroke([[24,0],[24,44]],x:250)]
        book.change(strokes: strokes)
        try await wait("local draft", until: { !book.localDrafts.isEmpty })
        try require(book.regions.count == 1, "Arithmetic row was split")
        let region = book.regions[0]
        guard let draft = book.localDraft(region) else { throw Failure(message: "No local draft") }
        print("Stroke fixture: \(draft.latex)")
        try require(draft.latex.replacingOccurrences(of: " ", with: "") == "2+2=4", "Arithmetic transcription was incorrect")
        book.select(region)
        try require(book.correction == draft.latex, "Selecting did not populate draft")
        book.accept()
        try await wait("save", until: { book.saveStatus == "Saved locally" })
        let restored = try InkDocument.decode(Data(contentsOf: file))
        try require(restored.expressions.count == 1 && restored.strokes == strokes, "Acceptance lost ink or text")
        book.undo()
        try require(book.document.expressions.isEmpty && book.document.strokes == strokes, "Undo acceptance damaged strokes")
        book.redo()
        try require(book.document.expressions.count == 1, "Redo acceptance failed")
        // Edit during the debounce window. Only the latest ink may publish.
        book.change(strokes: [stroke(two,x:30)])
        book.change(strokes: strokes)
        try await wait("restored region", until: { book.regions.count == 1 && book.regions[0].strokes.count == strokes.count })
        try require(book.accepted(book.regions[0]) != nil, "Accepted source was overwritten")
        try await wait("final save", until: { book.saveStatus == "Saved locally" })
        book.clearPage()
        try require(book.document.strokes.isEmpty && book.document.expressions.isEmpty, "Clear page failed")
        book.undo()
        try require(book.document.strokes == strokes && book.document.expressions.count == 1, "Undo clear failed")
        // Actual application view, rendered offscreen without accessibility access.
        let hosting = NSHostingView(rootView: Workspace(book: book).preferredColorScheme(.light))
        hosting.frame = CGRect(x: 0, y: 0, width: 1100, height: 850)
        hosting.layoutSubtreeIfNeeded()
        func webViews(_ view: NSView) -> [WKWebView] {
            (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap(webViews)
        }
        try await Task.sleep(for: .milliseconds(300))
        guard let acceptedPreview = webViews(hosting).first else { throw Failure(message: "Accepted preview is absent from the real view") }
        var acceptedRendered = false
        for _ in 0..<50 {
            if let value = try? await acceptedPreview.evaluateJavaScript("!!document.querySelector('.katex')") as? Bool, value {
                acceptedRendered = true; break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        try require(acceptedRendered, "Accepted math did not render in the real view")
        if let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) {
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            if let png = bitmap.representation(using: .png, properties: [:]) {
                let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("artifacts/native-workspace-check.png")
                try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
                try png.write(to: output)
            }
        }
        try await wait("save after undo clear", until: { book.saveStatus == "Saved locally" })

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DelayedOCRProtocol.self]
        let session = URLSession(configuration: configuration)
        let staleBook = Notebook(storageURL: directory.appendingPathComponent("stale.json"), localSession: session)
        var stalePublished = false
        let observation = staleBook.$localDrafts.sink { drafts in
            if drafts.values.contains(where: { $0.latex == "999" }) { stalePublished = true }
        }
        staleBook.change(strokes: [stroke(two, x: 30)])
        try await wait("first delayed request", until: { DelayedOCRProtocol.requests == 1 })
        staleBook.change(strokes: strokes)
        try await wait("newer response", until: { staleBook.localDrafts.values.contains { $0.latex == "2+2=4" } })
        try require(!stalePublished && DelayedOCRProtocol.requests == 2, "Stale result published or duplicate requests queued")
        try await wait("stale test save", until: { staleBook.saveStatus == "Saved locally" })
        observation.cancel()
        session.invalidateAndCancel()
        DelayedOCRProtocol.requests = 0
        DelayedOCRProtocol.failFirst = true
        let modeSession = URLSession(configuration: configuration)
        let modeBook = Notebook(storageURL: directory.appendingPathComponent("mode.json"), localSession: modeSession)
        modeBook.recognitionMode = "numbers"
        modeBook.change(strokes: strokes)
        try await wait("numeric request", until: { DelayedOCRProtocol.requests == 1 })
        modeBook.busy = true
        modeBook.recognitionMode = "math"
        modeBook.changeRecognitionMode()
        try require(!modeBook.busy, "Changing mode left cloud busy")
        try await wait("new mode response after stale 422", until: { !modeBook.localDrafts.isEmpty })
        try require(!modeBook.localFailed(modeBook.regions[0]), "Old numeric failure blocked Algebra mode")
        try require(DelayedOCRProtocol.requests == 2, "Mode change did not retry the new mode")
        try await wait("mode test save", until: { modeBook.saveStatus == "Saved locally" })
        modeSession.invalidateAndCancel()

        let mathHost = NSHostingView(rootView: MathPreview(latex: "\\frac{x^{2}+3x}{2}=7"))
        mathHost.frame = CGRect(x: 0, y: 0, width: 600, height: 180)
        mathHost.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(100))
        guard let web = webViews(mathHost).first else { throw Failure(message: "Math view is missing") }
        var rendered = false
        for _ in 0..<100 {
            try await Task.sleep(for: .milliseconds(100))
            if let value = try? await web.evaluateJavaScript("!!document.querySelector('.katex')") as? Bool, value {
                rendered = true; break
            }
        }
        try require(rendered, "Bundled KaTeX failed to render in WKWebView")
        let image = try await web.takeSnapshot(configuration: nil)
        if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
            let output = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("artifacts/native-math-check.png")
            try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
            try png.write(to: output)
        }
        let digitBook = Notebook(storageURL: directory.appendingPathComponent("digit.json"))
        digitBook.recognitionMode = "numbers"
        digitBook.change(strokes: [stroke([[0,0],[28,3],[30,8],[0,52]], x: 70)])
        try await wait("single digit draft", until: { !digitBook.localDrafts.isEmpty })
        try require(digitBook.localDrafts.values.first?.latex == "7", "Single digit was not recognized as 7")
        let digitHost = NSHostingView(rootView: Workspace(book: digitBook).preferredColorScheme(.light))
        digitHost.frame = CGRect(x: 0, y: 0, width: 1100, height: 800)
        digitHost.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        guard let digitWeb = webViews(digitHost).first else { throw Failure(message: "Live draft math view is missing") }
        var digitRendered = false
        for _ in 0..<50 {
            if let value = try? await digitWeb.evaluateJavaScript("!!document.querySelector('.katex') && document.querySelector('.katex-html').innerText.trim() === '7'") as? Bool, value {
                digitRendered = true; break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        try require(digitRendered, "The live local draft box did not render 7")
        let digitImage = try await digitWeb.takeSnapshot(configuration: nil)
        guard let tiff = digitImage.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
            throw Failure(message: "Could not capture live draft pixels")
        }
        var darkSamples = 0
        for y in stride(from: 8, to: bitmap.pixelsHigh - 8, by: 3) {
            for x in stride(from: 8, to: bitmap.pixelsWide - 8, by: 3) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   color.redComponent < 0.6 && color.greenComponent < 0.6 && color.blueComponent < 0.6 {
                    darkSamples += 1
                }
            }
        }
        try require(darkSamples > 10, "Live draft has a DOM but its rendered image is blank")
        try png.write(to: URL(fileURLWithPath: "artifacts/native-digit-draft.png"))
        try await wait("digit save", until: { digitBook.saveStatus == "Saved locally" })
        print("Packaged live draft rendered 7; image saved to artifacts/native-digit-draft.png")
        let examples = PracticeTopic.all.flatMap { $0.examples }
        try require(examples.count >= 60 && Set(examples.map { $0.id }).count == examples.count, "Practice catalog is incomplete or has duplicate IDs")
        try require(PracticeTopic.matching(topic: "Numbers", query: "").count == 8, "Topic filtering failed")
        try require(PracticeTopic.matching(topic: "All topics", query: "SIGMA").count == 1, "Case-insensitive symbol search failed")
        try require(PracticeTopic.matching(topic: "All topics", query: "μ").count == 1, "Greek symbol search failed")
        try require(PracticeTopic.matching(topic: "Calculus", query: "factorials").isEmpty, "Search escaped the selected topic")
        try require(PracticeTopic.matching(topic: "All topics", query: "no such example").isEmpty, "Empty search failed")
        let catalogData = examples.map { ["title": $0.title, "latex": $0.latex, "mode": $0.mode] }
        try JSONSerialization.data(withJSONObject: catalogData, options: [.prettyPrinted]).write(to: URL(fileURLWithPath: "artifacts/practice-examples.json"))
        let sampleWeb = WKWebView(frame: CGRect(x: 0, y: 0, width: 500, height: 160))
        let renderer = MathRenderState()
        var completedExample: String?
        var exampleError: String?
        renderer.onResult = { value, error in completedExample = value; exampleError = error }
        renderer.start(sampleWeb)
        for example in examples {
            completedExample = nil; exampleError = nil
            renderer.update(example.latex, in: sampleWeb)
            try await wait("example " + example.title, until: { completedExample == example.latex })
            try require(exampleError == nil, "Example failed to render: " + example.title)
        }
        let gallery = NSHostingView(rootView: PracticeGallery())
        gallery.frame = CGRect(x: 0, y: 0, width: 900, height: 700)
        gallery.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .seconds(1))
        if let bitmap = gallery.bitmapImageRepForCachingDisplay(in: gallery.bounds) {
            gallery.cacheDisplay(in: gallery.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                try data.write(to: URL(fileURLWithPath: "artifacts/native-examples-gallery.png"))
            }
        }
        gallery.frame = CGRect(x: 0, y: 0, width: 420, height: 740)
        gallery.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(300))
        if let bitmap = gallery.bitmapImageRepForCachingDisplay(in: gallery.bounds) {
            gallery.cacheDisplay(in: gallery.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) {
                try data.write(to: URL(fileURLWithPath: "artifacts/native-examples-narrow.png"))
            }
        }
        print("All \(examples.count) practice expressions rendered in the packaged app")

        if let index = CommandLine.arguments.firstIndex(of: "--fixtures"), CommandLine.arguments.count > index + 1 {
            try await checkFixtures(URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        }
        print("Checked stroke capture, local inference, review, acceptance, persistence, undo/redo, edit coalescing, and native math rendering")
    }
    static func checkFixtures(_ directory: URL) async throws {
        struct Fixture: Decodable { let label: String; let strokes: [[[Double]]] }
        var results: [[String: Any]] = []
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).sorted(by: { $0.path < $1.path }) where url.pathExtension == "json" {
            guard let fixture = try? JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url)) else { continue }
            let points = fixture.strokes.flatMap { $0 }
            let scale = min(1, 900 / max(1, points.map { $0[0] }.max() ?? 1), 1000 / max(1, points.map { $0[1] }.max() ?? 1))
            let strokes = fixture.strokes.map { points in InkStroke(points: points.map { InkPoint(x: $0[0] * scale, y: $0[1] * scale) }) }
            let rows = ShadowRecognizer().regions(strokes)
            guard let image = inkPNG(strokes) else { throw Failure(message: "PNG capture failed") }
            var request = URLRequest(url: URL(string: "http://127.0.0.1:8002/recognize")!)
            request.httpMethod = "POST"; request.timeoutInterval = 60
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["image": "data:image/png;base64," + image.base64EncodedString()])
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
            results.append(["id": url.deletingPathExtension().lastPathComponent, "expected": fixture.label, "actual": response["latex"] ?? "", "rows": rows.count, "seconds": response["seconds"] ?? 0, "alternatives": response["alternatives"] ?? []])
        }
        try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "artifacts/native-fixtures-results.json"))
        print("Native raster and segmentation tested on \(results.count) handwriting fixtures")
    }
}

/// Deterministic transport for an edit made while inference is already running.
final class DelayedOCRProtocol: URLProtocol {
    static var requests = 0
    static var failFirst = false
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        DispatchQueue.main.async {
            Self.requests += 1
            let index = Self.requests
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                guard !self.stopped else { return }
                let body = try! JSONSerialization.data(withJSONObject: ["latex": index == 1 ? "999" : "2+2=4", "seconds": 0.8, "alternatives": []] as [String: Any])
                self.client?.urlProtocol(self, didReceive: HTTPURLResponse(url: self.request.url!, statusCode: Self.failFirst && index == 1 ? 422 : 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
                self.client?.urlProtocol(self, didLoad: body)
                self.client?.urlProtocolDidFinishLoading(self)
            }
        }
    }
    override func stopLoading() { DispatchQueue.main.async { self.stopped = true } }
}
#endif
