/* Tracks ink regions, consolidates bracket-bounded matrix fragments and preserves recognition freshness and page-local math context. */
import Foundation
import SwiftData
import CoreGraphics

@MainActor
protocol StepTracking {
    func process(drawingData: Data, page: Page, context: ModelContext) async
}

@MainActor
@Observable
final class StepTrackingCoordinator: StepTracking {
    private(set) var alternatives: [UUID: [String]] = [:]
    private(set) var durations: [UUID: Int] = [:]
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
        await process(drawingData: drawingData, page: page, context: context, force: false)
    }

    func process(drawingData: Data, page: Page, context: ModelContext, force: Bool) async {
        let processingMode = page.mathMode
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
                // A bracket pair supplies explicit ownership when old recognition split the matrix into fragments.
                groupingIsAmbiguous = !region.isBoundedMatrix && (candidates.dropFirst().first.map { best.1 - $0.1 < 0.1 } ?? false)
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
                step.invalidateAcceptance()
                step.inkData = region.inkData
                step.bounds = region.bounds
                step.strokeFingerprint = region.fingerprint
                step.status = .unchecked
                step.recognitionState = groupingIsAmbiguous ? .ambiguous : .recognizing
                step.updatedAt = Date()
                changedSteps.append((step, groupingIsAmbiguous))
            } else if step.isAccepted {
                continue
            } else if force || step.recognitionProviderRaw != recognizer.identifier || hasLegacyPlaceholder || [.collecting, .recognizing, .failed].contains(step.recognitionState) {
                step.recognitionState = groupingIsAmbiguous ? .ambiguous : .recognizing
                step.updatedAt = Date()
                changedSteps.append((step, groupingIsAmbiguous))
            }
        }

        for step in availableSteps where !matchedStepIDs.contains(step.stableID) {
            step.isActive = false
            step.invalidateAcceptance()
            step.updatedAt = Date()
        }

        reorderActiveSteps(on: page)
        ProblemContextMathService.refresh(page:page)
        try? context.save()

        for (step, groupingIsAmbiguous) in changedSteps {
            guard !Task.isCancelled, currentDrawingMatches(drawingFingerprint, page: page) && page.mathMode == processingMode else { return }
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
                guard !Task.isCancelled, currentDrawingMatches(drawingFingerprint, page: page) && page.mathMode == processingMode else { return }
#if DEBUG
                await RecognitionDebugRecorder.shared.record(context: debugContext, result: result)
#endif
                guard !Task.isCancelled, currentDrawingMatches(drawingFingerprint, page: page), page.mathMode == processingMode else { return }
                alternatives[step.stableID] = result.candidates.map(\.text)
                durations[step.stableID] = result.durationMilliseconds
                step.recognitionProviderRaw = recognizer.identifier
                step.recognitionMilliseconds = result.durationMilliseconds
                step.recognitionConfidence = result.confidence ?? 0
                if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    step.recognitionState = .failed
                    step.status = .unchecked
                    step.label = "No math recognized"
                    step.explanation = "The recognizer did not recognize this row. Its ink and debug image have been preserved."
                } else if (result.confidence ?? 0) >= recognitionThreshold {
                    step.recognizedText = result.text
                    step.ghostLaTeX = result.latex
                    step.label = result.text
                    step.recognitionState = .ready
                    step.status = .unchecked
                    step.explanation = "Recognition draft. Mathematics has not been verified."
                } else {
                    step.recognizedText = result.text
                    step.ghostLaTeX = result.latex
                    step.label = result.text
                    step.recognitionState = .ambiguous
                    step.status = .unchecked
                    step.explanation = result.confidence == nil
                        ? "Model draft; confidence is not calibrated. Mathematics has not been verified."
                        : "Recognition confidence is low. The original ink has been preserved."
                }
            } catch {
                guard !Task.isCancelled else { return }
                guard currentDrawingMatches(drawingFingerprint, page: page) && page.mathMode == processingMode else { return }
#if DEBUG
                await RecognitionDebugRecorder.shared.recordFailure(context: debugContext, error: error)
#endif
                guard !Task.isCancelled, currentDrawingMatches(drawingFingerprint, page: page), page.mathMode == processingMode else { return }
                step.recognitionState = .failed
                step.status = .unchecked
                step.label = "Unrecognized handwriting"
                step.explanation = "\(error.localizedDescription) Original ink is preserved. Check recognition settings and tap Recognize again."
            }

            step.updatedAt = Date()
            appendRevisionIfNeeded(to: step, context: context)
        }

        ProblemContextMathService.refresh(page:page)
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
