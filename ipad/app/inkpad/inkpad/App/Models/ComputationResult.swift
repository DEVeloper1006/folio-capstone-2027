import Foundation
import CoreGraphics
import SwiftData

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
    var isCurrent: Bool {
        guard let source else { return false }
        return !isRemoved && source.isAccepted && source.acceptedLatex == inputLatex
            && source.acceptedFingerprint == sourceFingerprint
            && source.latestAcceptedRevisionNumber == sourceRevisionNumber
    }
}
