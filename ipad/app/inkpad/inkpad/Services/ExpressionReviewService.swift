/* Accepts reviewed transcriptions, refreshes inferred problem scopes and saves recognition benchmark samples. */
import Foundation
import SwiftData

enum ExpressionReviewError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let value) = self { value } else { nil } }
}

nonisolated struct RecognitionBenchmarkSample: Sendable {
    nonisolated struct Record: Codable, Sendable {
        let id: UUID
        let stepID: UUID
        let date: Date
        let source: String
        let provider: String
        let localModelRevision: String?
        let predictedLatex: String
        let expectedLatex: String
        let recognitionMilliseconds: Int
        let strokeFingerprint: String
    }
    let record: Record
    let ink: Data
    let png: Data
}

@MainActor
enum ExpressionReviewService {
    /// Acceptance confirms transcription only. Mathematical correctness stays unchecked.
    static func accept(_ step: Step, latex: String, page: Page, context: ModelContext,
                       source: String = "user-reviewed") throws -> RecognitionBenchmarkSample? {
        let value = latex.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 10_000 else {
            throw ExpressionReviewError.invalid("Enter LaTeX between 1 and 10,000 characters.")
        }
        guard step.page === page, step.isActive, step.source == .inferred,
              ![.collecting, .recognizing, .failed].contains(step.recognitionState),
              let ink = step.inkData, let drawing = page.drawingData,
              SpatialInkSegmenter().regions(in: drawing).contains(where: { $0.fingerprint == step.strokeFingerprint }) else {
            throw ExpressionReviewError.invalid("This row changed. Tap Recognize and review the current ink first.")
        }
        if step.isAccepted, step.acceptedLatex == value { return nil }
        let png = try RowInkRenderer.renderPNG(inkData: ink)
        let old = (step.acceptedLatex, step.acceptedFingerprint, step.acceptedAt, step.ghostLaTeX,
                   step.label, step.recognitionStateRaw, step.statusRaw, step.explanation, step.updatedAt)
        let revision = StepRevision(revisionNumber: (step.revisions.map(\.revisionNumber).max() ?? 0) + 1,
            inkData: ink, strokeFingerprint: step.strokeFingerprint, recognizedText: step.recognizedText,
            latex: value, status: .unchecked)
        revision.isUserAccepted = true
        revision.recognitionProviderRaw = step.recognitionProviderRaw
        revision.step = step; step.revisions.append(revision); context.insert(revision)
        step.acceptedLatex = value; step.acceptedFingerprint = step.strokeFingerprint; step.acceptedAt = Date()
        step.ghostLaTeX = value; step.label = value; step.recognitionState = .ready; step.status = .unchecked
        step.explanation = "Transcription reviewed by you. Mathematics has not been verified."
        step.updatedAt = Date(); page.notebook?.lastEditedAt = Date()
        let previousContext=page.steps.map { ($0,$0.problemGroupID,$0.problemIntentRaw,$0.problemASTJSON) }
        ProblemContextMathService.refresh(page:page)
        do { try context.save() }
        catch {
            for (row,group,meaning,ast) in previousContext { row.problemGroupID=group;row.problemIntentRaw=meaning;row.problemASTJSON=ast }
            step.acceptedLatex = old.0; step.acceptedFingerprint = old.1; step.acceptedAt = old.2
            step.ghostLaTeX = old.3; step.label = old.4; step.recognitionStateRaw = old.5
            step.statusRaw = old.6; step.explanation = old.7; step.updatedAt = old.8
            step.revisions.removeAll { $0 === revision }; context.delete(revision)
            throw error
        }
        let prediction = step.recognitionProviderRaw == "vision"
            ? SimpleMathLaTeXNormalizer.normalize(step.recognizedText) : step.recognizedText
        return RecognitionBenchmarkSample(record: .init(id: UUID(), stepID: step.stableID, date: Date(),
            source: source, provider: step.recognitionProviderRaw,
            localModelRevision: step.recognitionProviderRaw == "local" ? "7b96df06b9d81cdb129c3bef68b7250bc3e2b0ea" : nil,
            predictedLatex: prediction, expectedLatex: value, recognitionMilliseconds: step.recognitionMilliseconds,
            strokeFingerprint: step.strokeFingerprint), ink: ink, png: png)
    }
}

actor RecognitionBenchmarkStore {
    static let shared = RecognitionBenchmarkStore()
    func save(_ sample: RecognitionBenchmarkSample) throws -> URL {
        let root = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RecognitionBenchmarks", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let folder = root.appendingPathComponent(sample.record.id.uuidString, isDirectory: true)
        let staging = root.appendingPathComponent(".pending-" + sample.record.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            try sample.ink.write(to: staging.appendingPathComponent("strokes.drawing"), options: .atomic)
            try sample.png.write(to: staging.appendingPathComponent("input.png"), options: .atomic)
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(sample.record).write(to: staging.appendingPathComponent("result.json"), options: .atomic)
            try FileManager.default.moveItem(at: staging, to: folder)
        } catch { try? FileManager.default.removeItem(at: staging); throw error }
        return folder
    }
}
