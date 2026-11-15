import Foundation
import SwiftData
import CoreGraphics
import PencilKit

@MainActor
enum MathResultStore {
    static func save(_ answer:MathComputationAnswer,page:Page,source:Step?,expected:IntegrationSourceSnapshot?,context:ModelContext) throws -> ComputationResult {
        try Task.checkCancellation()
        let encoded=try answer.request.encoded()
        let step:Step
        var created:Step?
        if let source,let expected {
            guard source.page === page,try PolynomialResultStore.snapshot(source)==expected,
                  answer.request.inputA.trimmingCharacters(in:.whitespacesAndNewlines)==expected.inputLatex.trimmingCharacters(in:.whitespacesAndNewlines) else {
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
        if let existing=step.computationResults.first(where:{$0.isCurrent && $0.requestJSON==encoded && $0.engineVersion==answer.engineVersion}) { return existing }
        let result=ComputationResult(mathAnswer:answer,source:step,requestJSON:encoded)
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
