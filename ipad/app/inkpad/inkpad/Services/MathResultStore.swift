/* Save native computation answers on their source row or typed-input row and guard them against changed source manifests. */
import Foundation
import SwiftData
import CoreGraphics
import PencilKit

@MainActor
enum MathResultStore {
    /// Persist an answer after validating its source snapshot, optional problem-prefix manifest and earlier solved-result dependencies.
    static func save(_ answer:MathComputationAnswer,page:Page,source:Step?,expected:IntegrationSourceSnapshot?,context:ModelContext,sourceContext:[ComputationSourceReference]=[],contextGroupID:UUID?=nil,sourceResults:[ComputationResultReference]=[]) throws -> ComputationResult {
        try Task.checkCancellation()
        let encoded=try answer.request.encoded()
        let contextEncoder=JSONEncoder();contextEncoder.outputFormatting=[.sortedKeys]
        let contextJSON=String(decoding:try contextEncoder.encode(sourceContext),as:UTF8.self)
        let resultsJSON=String(decoding:try contextEncoder.encode(sourceResults),as:UTF8.self)
        for reference in sourceResults {
            guard let source,let row=page.steps.first(where:{$0.stableID==reference.sourceID}),row.sortIndex<source.sortIndex,
                  row.problemGroupID==source.problemGroupID,
                  let result=row.computationResults.first(where:{$0.stableID==reference.stableID}),result.isCurrent,
                  result.outputLatex==reference.outputLatex,result.requestJSON==reference.requestJSON else {
                throw PolynomialError.invalid("An earlier solved result changed. Recompute that row first.")
            }
        }
        if !sourceContext.isEmpty {
            guard let contextGroupID,let source,source.problemGroupID==contextGroupID,
                  sourceContext==ProblemContextMathService.manifest(page:page,groupID:contextGroupID,through:source) else {
                throw PolynomialError.invalid("A grouped problem row changed. Review the problem rows and compute again.")
            }
        } else if contextGroupID != nil { throw PolynomialError.invalid("A contextual result needs at least one grouped definition source.") }
        let step:Step
        var created:Step?
        if let source,let expected {
            guard source.page === page,try PolynomialResultStore.snapshot(source)==expected,
                  answer.inputLatex.trimmingCharacters(in:.whitespacesAndNewlines)==expected.inputLatex.trimmingCharacters(in:.whitespacesAndNewlines),
                  (answer.request.inputA.trimmingCharacters(in:.whitespacesAndNewlines)==expected.inputLatex.trimmingCharacters(in:.whitespacesAndNewlines) || !sourceContext.isEmpty) else {
                throw PolynomialError.invalid("The source changed. Review it and compute again.")
            }
            step=source
        } else {
            guard source==nil,expected==nil else { throw PolynomialError.invalid("The source snapshot is incomplete.") }
            if let previous=page.steps.first(where: { $0.source == .manual && $0.isActive && $0.computationResults.contains(where:{$0.requestJSON==encoded && $0.isCurrent}) }) { step=previous }
            else {
                var input=answer.inputLatex
                if answer.request.operation.needsB {
                    let second=answer.request.operation.isMatrix ? try ExactMatrix.parse(answer.request.inputB).latex:answer.request.inputB
                    input="A="+input+",\\quad B="+second
                }
                let value=Step(sortIndex:page.steps.count,status:.unchecked,label:input,ghostLaTeX:input,source:.manual)
                let fingerprint="typed:"+SpatialInkSegmenter.drawingFingerprint(Data(encoded.utf8))
                value.strokeFingerprint=fingerprint;value.acceptedFingerprint=fingerprint;value.acceptedLatex=input;value.acceptedAt=Date()
                value.recognitionProviderRaw="typed";value.explanation="Typed computation input, independent of handwriting recognition."
                let drawing=page.drawingData.flatMap { try? PKDrawing(data:$0) } ?? PKDrawing()
                let bounds=drawing.bounds
                let anchorY = !bounds.isNull && bounds.maxY.isFinite ? max(80,bounds.maxY+24):80
                value.bounds=CGRect(x:24,y:anchorY,width:0,height:0)
                let revision=StepRevision(revisionNumber:1,inkData:nil,strokeFingerprint:fingerprint,recognizedText:input,latex:input,status:.unchecked)
                revision.isUserAccepted=true;revision.recognitionProviderRaw="typed";revision.step=value;value.revisions.append(revision)
                value.page=page;page.steps.append(value);context.insert(value);context.insert(revision);step=value;created=value
            }
        }
        if let existing=step.computationResults.first(where:{$0.isCurrent && $0.requestJSON==encoded && $0.sourceContextJSON==contextJSON && $0.sourceResultsJSON==resultsJSON && $0.sourceContextGroupID==contextGroupID && $0.engineVersion==answer.engineVersion}) { return existing }
        let result=ComputationResult(mathAnswer:answer,source:step,requestJSON:encoded)
        result.sourceContextJSON=contextJSON;result.sourceResultsJSON=resultsJSON;result.sourceContextGroupID=contextGroupID
        result.source=step;step.computationResults.append(result);context.insert(result)
        page.notebook?.lastEditedAt=Date()
        do { try context.save() }
        catch {
            step.computationResults.removeAll {$0 === result};context.delete(result)
            if let created { page.steps.removeAll {$0 === created};context.delete(created) }
            throw error
        }
        return result
    }
}
