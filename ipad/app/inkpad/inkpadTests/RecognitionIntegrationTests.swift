import XCTest
import PencilKit
import SwiftData
import SwiftUI
import WebKit
@testable import inkpad

final class RecognitionIntegrationTests: XCTestCase {
    @MainActor
    private func ink() -> Data {
        let points = [CGPoint(x: 20, y: 20), CGPoint(x: 100, y: 60)].enumerated().map { index, p in
            PKStrokePoint(location: p, timeOffset: Double(index) * 0.1, size: CGSize(width: 3, height: 3),
                          opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
        }
        return PKDrawing(strokes: [PKStroke(ink: PKInk(.pen, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date()))]).dataRepresentation()
    }

    @MainActor
    func testMacRequestAndUnknownConfidence() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecognitionHTTPStub.self]
        let service = MacMathRecognitionService(connection: .init(provider: "mac", serverURL: "https://mac.local:8002", token: "test-token"),
                                                session: URLSession(configuration: configuration))
        let result = try await service.recognize(inkData: ink(), mode: .calc)
        XCTAssertEqual(result.latex, #"\frac{x}{2}"#)
        XCTAssertNil(result.confidence)
        XCTAssertEqual(result.candidates.count, 2)
        XCTAssertNotNil(result.debugImagePNG)
        let health = try await service.health()
        XCTAssertEqual(health, "TexTeller + Grade 12 adapter")
    }

    @MainActor
    func testWorkerFailuresAreVisible() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RecognitionHTTPStub.self]
        let session = URLSession(configuration: configuration)
        for host in ["unauthorized.local", "forbidden.local", "unreadable.local", "empty.local", "malformed.local", "timeout.local", "busy.local"] {
            let service = MacMathRecognitionService(connection: .init(provider: "mac", serverURL: "https://" + host, token: "test-token"), session: session)
            do {
                _ = try await service.recognize(inkData: ink(), mode: .calc)
                XCTFail("Expected a visible error for " + host)
            } catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        }
    }

    func testInvalidServerURLRejected() {
        for value in ["", "file:///tmp/test", "https://mac.local/path", "https://user:password@mac.local", "https://mac.local?key=test"] {
            XCTAssertThrowsError(try RecognitionConnection(provider: "mac", serverURL: value, token: "test").baseURL())
        }
    }

    @MainActor
    func testCancelledRowCanBeRetriedAndDraftIsUnchecked() async throws {
        let schema = Schema([Page.self, Step.self, StepRevision.self, ComputationResult.self, Notebook.self, Branch.self, Snapshot.self,
                             Insight.self, ChatThread.self, ChatMessage.self, ClassSpace.self, WorkedExample.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let page = Page(sortIndex: 0)
        container.mainContext.insert(page)
        let data = ink()
        page.drawingData = data
        let slow = SlowRecognitionStub()
        let coordinator = StepTrackingCoordinator(recognizer: slow)
        let task = Task { await coordinator.process(drawingData: data, page: page, context: container.mainContext) }
        while !slow.started { await Task.yield() }
        task.cancel()
        await task.value
        XCTAssertNotEqual(page.steps.first?.ghostLaTeX, "stale")
        let retry = StepTrackingCoordinator(recognizer: ImmediateRecognitionStub())
        await retry.process(drawingData: data, page: page, context: container.mainContext)
        XCTAssertEqual(page.steps.count, 1)
        XCTAssertEqual(page.steps.first?.ghostLaTeX, "x^2")
        XCTAssertEqual(page.steps.first?.status, .unchecked)
        XCTAssertEqual(page.steps.first?.recognitionState, .ambiguous)
        XCTAssertEqual(retry.alternatives[page.steps[0].stableID], ["x^2", "x^3"])
    }

    @MainActor
    func testEditedInkRejectsDelayedResult() async throws {
        let schema = Schema([Page.self, Step.self, StepRevision.self, ComputationResult.self, Notebook.self, Branch.self, Snapshot.self,
                             Insight.self, ChatThread.self, ChatMessage.self, ClassSpace.self, WorkedExample.self])
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)])
        let page = Page(sortIndex: 0)
        container.mainContext.insert(page)
        let data = ink(); page.drawingData = data
        let slow = SlowRecognitionStub()
        let coordinator = StepTrackingCoordinator(recognizer: slow)
        let task = Task { await coordinator.process(drawingData: data, page: page, context: container.mainContext) }
        while !slow.started { await Task.yield() }
        page.drawingData = PKDrawing().dataRepresentation()
        await task.value
        XCTAssertNotEqual(page.steps.first?.ghostLaTeX, "stale")
        await coordinator.process(drawingData: page.drawingData!, page: page, context: container.mainContext)
        XCTAssertTrue(page.steps.allSatisfy { !$0.isActive })
    }

    @MainActor
    func testBundledMathJaxRendersAndTreatsLatexAsText() async throws {
        let view = MathJaxWebView(steps: [TypesetStep(latex: #"\frac{x^2}{2}"#, markdown: "", status: nil)])
        let controller = UIHostingController(rootView: view)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 500, height: 220)
        window.rootViewController = controller; window.makeKeyAndVisible()
        defer { window.isHidden = true }
        func web(in view: UIView) -> WKWebView? {
            if let web = view as? WKWebView { return web }
            return view.subviews.compactMap { web(in: $0) }.first
        }
        var rendered = false
        for _ in 0..<100 {
            if let webView = web(in: controller.view),
               let count = try? await webView.evaluateJavaScript("document.querySelectorAll('mjx-container svg').length"),
               (count as? Int ?? 0) > 0 { rendered = true; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        if !rendered {
            if let w = web(in: controller.view) {
                let diagnostics = try? await w.evaluateJavaScript("JSON.stringify({ready:document.readyState,mathjax:typeof MathJax,render:typeof window.renderRows,body:document.body.innerHTML})")
                XCTFail("MathJax did not render: \(String(describing: diagnostics))")
            } else { XCTFail("Hosting view did not create WKWebView") }
        }
        if let webView = web(in: controller.view) {
            let image = try await webView.takeSnapshot(configuration: nil)
            XCTAssertGreaterThan(image.pngData()?.count ?? 0, 1000)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Bundled MathJax fraction"
            attachment.lifetime = .keepAlways
            add(attachment)
            _ = try await webView.callAsyncJavaScript("await window.renderRows(rows)",
                arguments: ["rows": ["<img src=x onerror=alert(1)>"]], in: nil, contentWorld: .page)
            let images = try await webView.evaluateJavaScript("document.querySelectorAll('img').length")
            XCTAssertEqual(images as? Int, 0)
        }
    }
}

private final class RecognitionHTTPStub: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
        if request.url?.host == "timeout.local" {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut)); return
        }
        let statuses = ["unauthorized.local": 401, "forbidden.local": 403, "unreadable.local": 422, "busy.local": 503]
        let status = statuses[request.url?.host ?? ""] ?? 200
        let body: String
        if request.url?.host == "empty.local" { body = #"{"latex":"","alternatives":[]}"# }
        else if request.url?.host == "malformed.local" { body = "[]" }
        else if request.url?.path == "/health" { body = #"{"ready":true,"profile":"grade12"}"# }
        else {
            XCTAssertEqual(request.httpMethod, "POST")
            if let data = request.httpBody,
               let payload = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                XCTAssertEqual(payload["mode"], "math")
                XCTAssertTrue(payload["image"]?.hasPrefix("data:image/png;base64,") == true)
            }
            body = #"{"latex":"\\frac{x}{2}","alternatives":["\\frac{x}{2}","x/2"],"seconds":0.2}"#
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@MainActor
private final class SlowRecognitionStub: RecognitionService {
    var started = false
    func recognize(inkData: Data, mode: MathMode) async throws -> RecognitionResult {
        started = true
        try? await Task.sleep(for: .milliseconds(150))
        return RecognitionResult(text: "stale", latex: "stale", confidence: nil)
    }
}
private struct ImmediateRecognitionStub: RecognitionService {
    func recognize(inkData: Data, mode: MathMode) async throws -> RecognitionResult {
        RecognitionResult(text: "x^2", latex: "x^2", confidence: nil,
                          candidates: [.init(text: "x^2", confidence: nil), .init(text: "x^3", confidence: nil)])
    }
}
