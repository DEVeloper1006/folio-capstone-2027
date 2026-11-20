/* Persisted computation cards retain the accepted input and source revision checks, including the rows used by contextual calculations. */
import Foundation
import CoreGraphics
import SwiftData

struct ComputationSourceReference:Codable,Equatable,Sendable {
    let stableID:UUID
    let acceptedRevisionNumber:Int
    let acceptedFingerprint:String
    let acceptedLatex:String
    let problemGroupID:UUID
    let rowIndex:Int
    let intentRaw:String
    let isAccepted:Bool
    let strokeFingerprint:String
}

struct ComputationResultReference:Codable,Equatable,Sendable {
    let stableID:UUID
    let sourceID:UUID
    let outputLatex:String
    let requestJSON:String
}

@Model
final class ComputationResult {
    var stableID: UUID = UUID()
    var operationRaw: String = "integral"
    var variable: String = "x"
    var sourceRevisionNumber: Int = 0
    var sourceFingerprint: String = ""
    var inputLatex: String = ""
    var outputLatex: String = ""
    var engineVersion: String = ""
    var requestJSON: String = ""
    var sourceContextJSON:String = "[]"
    var sourceResultsJSON:String = "[]"
    var sourceContextGroupID:UUID? = nil
    var explanationStepsJSON: String = "[]"
    var createdAt: Date = Date()
    var isRemoved: Bool = false
    var isPlacedOnCanvas: Bool = false
    var canvasX: Double = 24
    var canvasY: Double = 160
    var canvasWidth: Double = 360
    var canvasHeight: Double = 190
    var canvasPreviewVersion:Int = 0
    @Attribute(.externalStorage) var canvasPreviewPNG: Data? = nil
    var source: Step?

    var canvasRect: CGRect { CGRect(x:canvasX,y:canvasY,width:canvasWidth,height:canvasHeight) }

    init(answer: PolynomialIntegrationAnswer, snapshot: IntegrationSourceSnapshot) {
        variable = answer.variable; inputLatex = snapshot.inputLatex; outputLatex = answer.latex
        sourceRevisionNumber = snapshot.revisionNumber; sourceFingerprint = snapshot.fingerprint
        engineVersion = answer.engineVersion
    }
    init(mathAnswer:MathComputationAnswer,source:Step,requestJSON:String) {
        operationRaw=mathAnswer.request.operation.rawValue;variable=mathAnswer.request.variable
        inputLatex=source.acceptedLatex;outputLatex=mathAnswer.outputLatex
        sourceRevisionNumber=source.latestAcceptedRevisionNumber;sourceFingerprint=source.acceptedFingerprint
        engineVersion=mathAnswer.engineVersion;self.requestJSON=requestJSON
        explanationStepsJSON=String(decoding:(try? JSONEncoder().encode(mathAnswer.steps)) ?? Data("[]".utf8),as:UTF8.self)
    }
    var operationTitle:String {
        operationRaw == "integral" ? "Antiderivative":MathOperation(rawValue:operationRaw)?.title ?? "Result"
    }
    var explanationSteps:[String] { (try? JSONDecoder().decode([String].self,from:Data(explanationStepsJSON.utf8))) ?? [] }
    var computationRequest:MathComputationRequest? { try? JSONDecoder().decode(MathComputationRequest.self,from:Data(requestJSON.utf8)) }
    var isCurrent: Bool { validatedCurrent(visiting:[]) }

    /// Validate earlier-row dependencies recursively with cycle/depth protection; later working cannot invalidate an earlier prefix.
    private func validatedCurrent(visiting:Set<UUID>)->Bool {
        guard !visiting.contains(stableID),visiting.count<32 else { return false }
        guard let source else { return false }
        guard !isRemoved && source.isAccepted && source.acceptedLatex == inputLatex
            && source.acceptedFingerprint == sourceFingerprint
            && source.latestAcceptedRevisionNumber == sourceRevisionNumber else { return false }
        guard sourceContextJSON != "[]" else { return true }
        guard let sourceContextGroupID,source.problemGroupID==sourceContextGroupID,source.problemIntent != .automatic,
              let references=try? JSONDecoder().decode([ComputationSourceReference].self,from:Data(sourceContextJSON.utf8)),
              let steps=source.page?.steps else { return false }
        let currentRows=steps.filter{$0.isActive && $0.problemGroupID==sourceContextGroupID && $0.sortIndex<=source.sortIndex}.sorted{$0.sortIndex<$1.sortIndex}
        guard currentRows.count==references.count else { return false }
        let rowsMatch=zip(references,currentRows).allSatisfy { reference,row in
            reference.stableID==row.stableID && row.latestAcceptedRevisionNumber==reference.acceptedRevisionNumber
                && row.acceptedFingerprint==reference.acceptedFingerprint && row.acceptedLatex==reference.acceptedLatex
                && row.problemGroupID==reference.problemGroupID && row.sortIndex==reference.rowIndex
                && row.problemIntent.rawValue==reference.intentRaw && row.isAccepted==reference.isAccepted
                && row.strokeFingerprint==reference.strokeFingerprint
        }
        guard rowsMatch,let resultReferences=try? JSONDecoder().decode([ComputationResultReference].self,from:Data(sourceResultsJSON.utf8)) else { return false }
        return resultReferences.allSatisfy { reference in
            guard let row=steps.first(where:{$0.stableID==reference.sourceID}),row.sortIndex<source.sortIndex,
                  let result=row.computationResults.first(where:{$0.stableID==reference.stableID}),
                  result.outputLatex==reference.outputLatex,result.requestJSON==reference.requestJSON else { return false }
            return result.validatedCurrent(visiting:visiting.union([stableID]))
        }
    }
}
