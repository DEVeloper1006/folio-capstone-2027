import XCTest
import SwiftData
import PencilKit
@testable import inkpad

@MainActor
final class ExpressionReviewTests: XCTestCase {
    private func container(url: URL? = nil) throws -> ModelContainer {
        let schema = Schema([Notebook.self, Page.self, Step.self, StepRevision.self, ComputationResult.self, Branch.self,
            ChatThread.self, ChatMessage.self, Snapshot.self, Insight.self, ClassSpace.self, WorkedExample.self])
        let configuration = url.map { ModelConfiguration(schema: schema, url: $0) }
            ?? ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func drawing(extra: Bool = false) -> Data {
        func stroke(_ y: CGFloat) -> PKStroke {
            let points = [CGPoint(x: 20, y: y), CGPoint(x: 100, y: y + 40)].enumerated().map { index, location in
                PKStrokePoint(location: location, timeOffset: Double(index) * 0.1,
                    size: CGSize(width: 3, height: 3), opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2)
            }
            return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date()))
        }
        return PKDrawing(strokes: extra ? [stroke(20), stroke(25)] : [stroke(20)]).dataRepresentation()
    }

    private func draft(in container: ModelContainer) async throws -> (Page, Step, CountingRecognizer) {
        let page = Page(sortIndex: 0); page.drawingData = drawing(); container.mainContext.insert(page)
        let recognizer = CountingRecognizer()
        await StepTrackingCoordinator(recognizer: recognizer).process(drawingData: page.drawingData!, page: page, context: container.mainContext)
        return (page, try XCTUnwrap(page.steps.first), recognizer)
    }

    func testStrokeFingerprintIncludesInkAndIntermediatePoints() throws {
        let raw = drawing(); let stroke = try XCTUnwrap(PKDrawing(data: raw).strokes.first)
        let recolored = PKStroke(ink: PKInk(.pen, color: .red), path: stroke.path)
        let recoloredData = PKDrawing(strokes: [recolored]).dataRepresentation()
        let first = try XCTUnwrap(SpatialInkSegmenter().regions(in: raw).first)
        let second = try XCTUnwrap(SpatialInkSegmenter().regions(in: recoloredData).first)
        XCTAssertNotEqual(first.fingerprint, second.fingerprint)
        XCTAssertEqual(first.fingerprint, SpatialInkSegmenter().regions(in: raw).first?.fingerprint)
        XCTAssertEqual(first.fingerprint, SpatialInkSegmenter().regions(in: try PKDrawing(data: raw).dataRepresentation()).first?.fingerprint)
    }

    func testRowCaptureRetainsForegroundInDarkAppearance() throws {
        var captured: Result<Data, Error>!
        let ink = drawing()
        UITraitCollection(userInterfaceStyle: .dark).performAsCurrent {
            captured = Result { try RowInkRenderer.renderPNG(inkData: ink) }
        }
        let png = try captured.get()
        let image = try XCTUnwrap(UIImage(data: png)?.cgImage)
        let prepared = try ImagePreprocessor.prepare(image)
        XCTAssertTrue(prepared.values.contains { $0 < -1 })
    }

    func testProviderRoutingDoesNotSilentlyFallBack() {
        XCTAssertTrue(RecognitionConnection(provider: "local").service() is LocalMathRecognitionService)
        XCTAssertTrue(RecognitionConnection(provider: "mac").service() is MacMathRecognitionService)
        XCTAssertTrue(RecognitionConnection(provider: "vision").service() is VisionMathRecognitionService)
    }

    func testAcceptCorrectionPreservesModelOutputInkAndUncheckedMath() async throws {
        let c = try container(); let (page, step, _) = try await draft(in: c)
        let ink = step.inkData
        let sample = try XCTUnwrap(ExpressionReviewService.accept(step, latex: " x^{2}+1 ", page: page, context: c.mainContext))
        XCTAssertTrue(step.isAccepted); XCTAssertEqual(step.acceptedLatex, "x^{2}+1")
        XCTAssertEqual(step.ghostLaTeX, "x^{2}+1"); XCTAssertEqual(step.recognizedText, "x")
        XCTAssertEqual(step.inkData, ink); XCTAssertEqual(step.status, .unchecked)
        XCTAssertEqual(step.revisions.filter(\.isUserAccepted).count, 1)
        XCTAssertEqual(sample.record.predictedLatex, "x"); XCTAssertEqual(sample.record.expectedLatex, "x^{2}+1")
        XCTAssertEqual(sample.ink, ink)
        XCTAssertNil(try ExpressionReviewService.accept(step, latex: "x^{2}+1", page: page, context: c.mainContext))
    }

    func testAcceptRejectsStaleAndEmptyCorrections() async throws {
        let c = try container(); let (page, step, _) = try await draft(in: c)
        XCTAssertThrowsError(try ExpressionReviewService.accept(step, latex: "  ", page: page, context: c.mainContext))
        page.drawingData = drawing(extra: true)
        XCTAssertThrowsError(try ExpressionReviewService.accept(step, latex: "x", page: page, context: c.mainContext))
        XCTAssertFalse(step.isAccepted)
    }

    func testForcedRecognitionAndProviderChangePreserveAcceptedCorrection() async throws {
        let c = try container(); let (page, step, _) = try await draft(in: c)
        _ = try ExpressionReviewService.accept(step, latex: "corrected", page: page, context: c.mainContext)
        let other = CountingRecognizer(identifier: "other")
        await StepTrackingCoordinator(recognizer: other).process(drawingData: page.drawingData!, page: page, context: c.mainContext, force: true)
        XCTAssertEqual(other.calls, 0); XCTAssertTrue(step.isAccepted); XCTAssertEqual(step.ghostLaTeX, "corrected")
    }

    func testInkEditInvalidatesAcceptanceAndRetainsAcceptedRevision() async throws {
        let c = try container(); let (page, step, recognizer) = try await draft(in: c)
        let originalInk = step.inkData
        _ = try ExpressionReviewService.accept(step, latex: "corrected", page: page, context: c.mainContext)
        let originalDrawing = try PKDrawing(data: originalInk!)
        let extraStroke = try PKDrawing(data: drawing(extra: true)).strokes.last!
        page.drawingData = PKDrawing(strokes: originalDrawing.strokes + [extraStroke]).dataRepresentation()
        await StepTrackingCoordinator(recognizer: recognizer).process(drawingData: page.drawingData!, page: page, context: c.mainContext)
        XCTAssertFalse(step.isAccepted)
        let revision = try XCTUnwrap(step.revisions.first(where: \.isUserAccepted))
        XCTAssertEqual(revision.inkData, originalInk); XCTAssertEqual(revision.latex, "corrected")
    }

    func testDeletedInkDeactivatesAcceptedObjectWithoutDeletingHistory() async throws {
        let c = try container(); let (page, step, recognizer) = try await draft(in: c)
        _ = try ExpressionReviewService.accept(step, latex: "x", page: page, context: c.mainContext)
        page.drawingData = PKDrawing().dataRepresentation()
        await StepTrackingCoordinator(recognizer: recognizer).process(drawingData: page.drawingData!, page: page, context: c.mainContext)
        XCTAssertFalse(step.isActive); XCTAssertFalse(step.isAccepted)
        XCTAssertEqual(step.revisions.filter(\.isUserAccepted).count, 1)
    }

    func testAcceptedExpressionAndRawDrawingSurviveNewContainer() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("review.store")
        func write() async throws -> UUID {
            let c = try container(url: url); let (page, step, _) = try await draft(in: c)
            _ = try ExpressionReviewService.accept(step, latex: "x^{2}", page: page, context: c.mainContext)
            return step.stableID
        }
        let id = try await write()
        let reopened = try container(url: url)
        let step = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Step>()).first(where: { $0.stableID == id }))
        XCTAssertTrue(step.isAccepted); XCTAssertEqual(step.acceptedLatex, "x^{2}")
        XCTAssertEqual(try PKDrawing(data: XCTUnwrap(step.inkData)).strokes.count, 1)
        XCTAssertEqual(step.revisions.filter(\.isUserAccepted).count, 1)
    }
}

@MainActor
private final class CountingRecognizer: RecognitionService {
    let identifier: String
    var calls = 0
    init(identifier: String = "test") { self.identifier = identifier }
    func recognize(inkData: Data, mode: MathMode) async throws -> RecognitionResult {
        calls += 1
        return RecognitionResult(text: "x", latex: "x", confidence: nil, durationMilliseconds: 5)
    }
}
