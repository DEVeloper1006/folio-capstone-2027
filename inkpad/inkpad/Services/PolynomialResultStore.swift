import Foundation
import SwiftData

nonisolated struct IntegrationSourceSnapshot: Equatable, Sendable {
    let stepID: UUID
    let revisionNumber: Int
    let fingerprint: String
    let inputLatex: String
}

@MainActor
enum PolynomialResultStore {
    static func snapshot(_ step: Step) throws -> IntegrationSourceSnapshot {
        guard step.isAccepted, ![.collecting, .recognizing, .failed].contains(step.recognitionState),
              let page = step.page, let ink = page.drawingData,
              SpatialInkSegmenter().regions(in: ink).contains(where: { $0.fingerprint == step.acceptedFingerprint }),
              let revision = step.revisions.first(where: { $0.isUserAccepted && $0.revisionNumber == step.latestAcceptedRevisionNumber }),
              revision.latex == step.acceptedLatex, revision.strokeFingerprint == step.acceptedFingerprint else {
            throw PolynomialError.invalid("Recognize and accept the current expression before integrating.")
        }
        return IntegrationSourceSnapshot(stepID: step.stableID, revisionNumber: revision.revisionNumber,
            fingerprint: step.acceptedFingerprint, inputLatex: step.acceptedLatex)
    }
    static func save(_ answer: PolynomialIntegrationAnswer, snapshot expected: IntegrationSourceSnapshot,
                     source: Step, context: ModelContext) throws -> ComputationResult {
        try Task.checkCancellation()
        guard try snapshot(source) == expected, answer.inputLatex == expected.inputLatex,
              answer.engineVersion == PolynomialIntegrationService.version else {
            throw PolynomialError.invalid("The source changed. Review it and integrate again.")
        }
        if let existing = source.computationResults.first(where: {
            $0.isCurrent && $0.variable == answer.variable && $0.engineVersion == answer.engineVersion && $0.operationRaw == "integral"
        }) { return existing }
        let result = ComputationResult(answer: answer, snapshot: expected)
        result.source = source; source.computationResults.append(result); context.insert(result)
        do { try context.save() }
        catch { source.computationResults.removeAll { $0 === result }; context.delete(result); throw error }
        return result
    }
    static func remove(_ result: ComputationResult, context: ModelContext) throws {
        let previous = result.isRemoved
        result.isRemoved = true
        do { try context.save() }
        catch { result.isRemoved = previous; throw error }
    }
}
