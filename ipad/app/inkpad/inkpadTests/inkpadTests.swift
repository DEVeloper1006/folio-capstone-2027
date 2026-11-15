//
//  inkpadTests.swift
//  inkpadTests
//
//  Created by Dev Mody on 2026-09-23.
//

import XCTest
import PencilKit
import SwiftData
@testable import inkpad

final class inkpadTests: XCTestCase {
    func testNearbyStrokesBecomeOneRegion() {
        let drawing = PKDrawing(strokes: [
            makeStroke(from: CGPoint(x: 20, y: 100), to: CGPoint(x: 40, y: 120)),
            makeStroke(from: CGPoint(x: 50, y: 102), to: CGPoint(x: 70, y: 122)),
        ])

        let regions = SpatialInkSegmenter().regions(in: drawing.dataRepresentation())

        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].strokeFingerprints.count, 2)
    }

    func testSeparatedLinesBecomeSeparateRegions() {
        let drawing = PKDrawing(strokes: [
            makeStroke(from: CGPoint(x: 20, y: 100), to: CGPoint(x: 80, y: 120)),
            makeStroke(from: CGPoint(x: 20, y: 240), to: CGPoint(x: 80, y: 260)),
        ])

        let regions = SpatialInkSegmenter().regions(in: drawing.dataRepresentation())

        XCTAssertEqual(regions.count, 2)
        XCTAssertLessThan(regions[0].bounds.minY, regions[1].bounds.minY)
    }

    func testHighlighterDoesNotCreateStepRegion() {
        let drawing = PKDrawing(strokes: [
            makeStroke(
                from: CGPoint(x: 20, y: 100),
                to: CGPoint(x: 80, y: 100),
                inkType: .marker
            ),
        ])

        XCTAssertTrue(SpatialInkSegmenter().regions(in: drawing.dataRepresentation()).isEmpty)
    }

    func testSegmentationFingerprintIsDeterministic() {
        let drawing = PKDrawing(strokes: [
            makeStroke(from: CGPoint(x: 20, y: 100), to: CGPoint(x: 80, y: 120)),
        ])
        let segmenter = SpatialInkSegmenter()

        let first = segmenter.regions(in: drawing.dataRepresentation())
        let second = segmenter.regions(in: drawing.dataRepresentation())

        XCTAssertEqual(first.first?.fingerprint, second.first?.fingerprint)
    }

    func testSimpleMathTextIsNormalizedToLatex() {
        let latex = SimpleMathLaTeXNormalizer.normalize("x² − 4 × y ≤ 10")

        XCTAssertEqual(latex, "x^{2} - 4 \\times y \\le 10")
    }

    @MainActor
    func testRowInkRendererProducesPNG() throws {
        let drawing = PKDrawing(strokes: [
            makeStroke(from: CGPoint(x: 20, y: 100), to: CGPoint(x: 80, y: 120)),
        ])

        let png = try RowInkRenderer.renderPNG(inkData: drawing.dataRepresentation())

        XCTAssertGreaterThan(png.count, 8)
        XCTAssertEqual(Array(png.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
    }

    @MainActor
    func testTrackingUpdatesExistingStepAndAddsRevision() async throws {
        let schema = Schema([
            Notebook.self, Page.self, Step.self, StepRevision.self, ComputationResult.self, Branch.self,
            ChatThread.self, ChatMessage.self, Snapshot.self, Insight.self,
            ClassSpace.self, WorkedExample.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = container.mainContext
        let page = Page(sortIndex: 0)
        context.insert(page)

        let firstDrawing = PKDrawing(strokes: [
            makeStroke(from: CGPoint(x: 20, y: 100), to: CGPoint(x: 80, y: 120)),
        ])
        let firstData = firstDrawing.dataRepresentation()
        let firstRegion = try XCTUnwrap(SpatialInkSegmenter().regions(in: firstData).first)
        page.drawingData = firstData

        await StepTrackingCoordinator(
            segmenter: StubSegmenter(region: firstRegion),
            recognizer: StubRecognizer()
        ).process(drawingData: firstData, page: page, context: context)

        let originalStep = try XCTUnwrap(page.steps.first)
        let originalID = originalStep.stableID
        XCTAssertEqual(originalStep.revisions.count, 1)

        let editedDrawing = PKDrawing(strokes: [
            makeStroke(from: CGPoint(x: 20, y: 100), to: CGPoint(x: 80, y: 120)),
            makeStroke(from: CGPoint(x: 85, y: 102), to: CGPoint(x: 100, y: 118)),
        ])
        let editedData = editedDrawing.dataRepresentation()
        let editedRegion = try XCTUnwrap(SpatialInkSegmenter().regions(in: editedData).first)
        page.drawingData = editedData

        await StepTrackingCoordinator(
            segmenter: StubSegmenter(region: editedRegion),
            recognizer: StubRecognizer()
        ).process(drawingData: editedData, page: page, context: context)

        XCTAssertEqual(page.steps.filter(\.isActive).count, 1)
        XCTAssertEqual(page.steps.first?.stableID, originalID)
        XCTAssertEqual(page.steps.first?.revisions.count, 2)
    }

    private func makeStroke(
        from start: CGPoint,
        to end: CGPoint,
        inkType: PKInk.InkType = .pen
    ) -> PKStroke {
        let points = [start, end].enumerated().map { index, location in
            PKStrokePoint(
                location: location,
                timeOffset: Double(index) * 0.1,
                size: CGSize(width: 2, height: 2),
                opacity: 1,
                force: 1,
                azimuth: 0,
                altitude: .pi / 2
            )
        }
        return PKStroke(
            ink: PKInk(inkType, color: .black),
            path: PKStrokePath(controlPoints: points, creationDate: Date())
        )
    }
}

private struct StubSegmenter: InkSegmenting {
    let region: InkRegion

    func regions(in drawingData: Data) -> [InkRegion] {
        [region]
    }
}

private struct StubRecognizer: RecognitionService {
    func recognize(inkData: Data, mode: MathMode) async throws -> RecognitionResult {
        RecognitionResult(text: "x = 1", latex: "x = 1", confidence: 0.99)
    }
}
