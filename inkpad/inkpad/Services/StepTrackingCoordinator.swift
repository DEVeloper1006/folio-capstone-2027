import Foundation
import SwiftData
import CoreGraphics

@MainActor
protocol StepTracking {
    func process(drawingData: Data, page: Page, context: ModelContext) async
}

@MainActor
final class StepTrackingCoordinator: StepTracking {
    private let segmenter: any InkSegmenting
    private let recognizer: any RecognitionService
    private let mathEngine: any MathEngine
    private let recognitionThreshold: Double

    init(
        segmenter: (any InkSegmenting)? = nil,
        recognizer: (any RecognitionService)? = nil,
        mathEngine: (any MathEngine)? = nil,
        recognitionThreshold: Double = 0.65
    ) {
        self.segmenter = segmenter ?? SpatialInkSegmenter()
        self.recognizer = recognizer ?? VisionMathRecognitionService()
        self.mathEngine = mathEngine ?? MockMathEngine()
        self.recognitionThreshold = recognitionThreshold
    }

    func process(drawingData: Data, page: Page, context: ModelContext) async {
        let drawingFingerprint = SpatialInkSegmenter.drawingFingerprint(drawingData)
        let regions = segmenter.regions(in: drawingData)
        var availableSteps = page.steps.filter { $0.source == .inferred }
        var matchedStepIDs = Set<UUID>()
        var changedSteps: [(Step, Bool)] = []

        for region in regions {
            let candidates = availableSteps
                .filter { !matchedStepIDs.contains($0.stableID) }
                .map { ($0, similarity(region: region, step: $0)) }
                .filter { $0.1 >= 0.15 }
                .sorted { $0.1 > $1.1 }

            let step: Step
            let groupingIsAmbiguous: Bool
            if let best = candidates.first {
                step = best.0
                groupingIsAmbiguous = candidates.dropFirst().first.map { best.1 - $0.1 < 0.1 } ?? false
            } else {
                step = Step(
                    sortIndex: page.steps.count,
                    status: .unchecked,
                    label: "Recognizing…",
                    yPosition: region.bounds.minY,
                    source: .inferred
                )
                step.page = page
                page.steps.append(step)
                context.insert(step)
                availableSteps.append(step)
                groupingIsAmbiguous = false
            }

            matchedStepIDs.insert(step.stableID)
            step.isActive = true
            let inkChanged = step.strokeFingerprint != region.fingerprint
            let hasLegacyPlaceholder = step.recognizedText.hasPrefix("Handwritten step (")
            if inkChanged {
                step.inkData = region.inkData
                step.bounds = region.bounds
                step.strokeFingerprint = region.fingerprint
                step.status = .unchecked
                step.recognitionState = groupingIsAmbiguous ? .ambiguous : .recognizing
                step.updatedAt = Date()
                changedSteps.append((step, groupingIsAmbiguous))
            } else if hasLegacyPlaceholder {
                step.recognitionState = groupingIsAmbiguous ? .ambiguous : .recognizing
                step.updatedAt = Date()
                changedSteps.append((step, groupingIsAmbiguous))
            }
        }

        for step in availableSteps where !matchedStepIDs.contains(step.stableID) {
            step.isActive = false
            step.updatedAt = Date()
        }

        reorderActiveSteps(on: page)
        try? context.save()

        for (step, groupingIsAmbiguous) in changedSteps {
            guard !Task.isCancelled, currentDrawingMatches(drawingFingerprint, page: page) else { return }
            guard !groupingIsAmbiguous, let inkData = step.inkData else {
                step.label = "Review step grouping"
                step.explanation = "This ink overlaps more than one existing step."
                appendRevisionIfNeeded(to: step, context: context)
                continue
            }

#if DEBUG
            let debugContext = makeDebugContext(step: step, page: page, inkData: inkData)
#endif

            do {
                let result = try await recognizer.recognize(inkData: inkData, mode: page.mathMode)
                guard !Task.isCancelled, currentDrawingMatches(drawingFingerprint, page: page) else { return }
#if DEBUG
                await RecognitionDebugRecorder.shared.record(context: debugContext, result: result)
#endif
                step.recognitionConfidence = result.confidence
                if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    step.recognitionState = .failed
                    step.status = .unchecked
                    step.label = "No math recognized"
                    step.explanation = "Vision did not recognize this row. Its ink and debug image have been preserved."
                } else if result.confidence >= recognitionThreshold {
                    step.recognizedText = result.text
                    step.ghostLaTeX = result.latex
                    step.label = result.text
                    step.recognitionState = .ready
                    step.status = mathEngine.checkStep(latex: result.latex, mode: page.mathMode)
                    step.explanation = mathEngine.explain(latex: result.latex, mode: page.mathMode)
                } else {
                    step.recognizedText = result.text
                    step.ghostLaTeX = result.latex
                    step.label = result.text
                    step.recognitionState = .ambiguous
                    step.status = .unchecked
                    step.explanation = "Recognition confidence is low. The original ink has been preserved."
                }
            } catch {
                guard currentDrawingMatches(drawingFingerprint, page: page) else { return }
#if DEBUG
                await RecognitionDebugRecorder.shared.recordFailure(context: debugContext, error: error)
#endif
                step.recognitionState = .failed
                step.status = .unchecked
                step.label = "Unrecognized handwriting"
                step.explanation = "Recognition failed. The original ink has been preserved."
            }

            step.updatedAt = Date()
            appendRevisionIfNeeded(to: step, context: context)
        }

        try? context.save()
    }

#if DEBUG
    private func makeDebugContext(step: Step, page: Page, inkData: Data) -> RecognitionDebugContext {
        let strokes = PKStrokeProvider().strokes(from: inkData)
        return RecognitionDebugContext(
            pageID: String(describing: page.persistentModelID),
            stepID: step.stableID,
            rowIndex: step.sortIndex,
            minX: step.bounds.minX,
            minY: step.bounds.minY,
            width: step.bounds.width,
            height: step.bounds.height,
            strokeCount: strokes.count,
            pointCount: strokes.reduce(0) { $0 + $1.count },
            fingerprint: step.strokeFingerprint
        )
    }
#endif

    private func currentDrawingMatches(_ expected: String, page: Page) -> Bool {
        guard let current = page.drawingData else { return false }
        return SpatialInkSegmenter.drawingFingerprint(current) == expected
    }

    private func similarity(region: InkRegion, step: Step) -> Double {
        let oldFingerprints = Set(step.strokeFingerprint.split(separator: "|").map(String.init))
        let newFingerprints = Set(region.strokeFingerprints)
        let sharedCount = oldFingerprints.intersection(newFingerprints).count
        let fingerprintScore = oldFingerprints.isEmpty
            ? 0
            : Double(sharedCount) / Double(max(oldFingerprints.count, newFingerprints.count))

        let intersection = step.bounds.intersection(region.bounds)
        let intersectionArea = intersection.isNull ? 0 : intersection.width * intersection.height
        let unionArea = step.bounds.width * step.bounds.height
            + region.bounds.width * region.bounds.height
            - intersectionArea
        let boundsScore = unionArea > 0 ? intersectionArea / unionArea : 0
        return max(fingerprintScore, boundsScore)
    }

    private func reorderActiveSteps(on page: Page) {
        let active = page.steps.filter(\.isActive).sorted {
            if abs($0.yPosition - $1.yPosition) > 8 { return $0.yPosition < $1.yPosition }
            return $0.boundsX < $1.boundsX
        }
        for (index, step) in active.enumerated() {
            step.sortIndex = index
        }
    }

    private func appendRevisionIfNeeded(to step: Step, context: ModelContext) {
        let latest = step.revisions.max { $0.revisionNumber < $1.revisionNumber }
        guard latest?.strokeFingerprint != step.strokeFingerprint
            || latest?.recognizedText != step.recognizedText
            || latest?.latex != step.ghostLaTeX
            || latest?.statusRaw != step.statusRaw else { return }

        let revision = StepRevision(
            revisionNumber: (latest?.revisionNumber ?? 0) + 1,
            inkData: step.inkData,
            strokeFingerprint: step.strokeFingerprint,
            recognizedText: step.recognizedText,
            latex: step.ghostLaTeX,
            status: step.status
        )
        revision.step = step
        step.revisions.append(revision)
        context.insert(revision)
    }
}
