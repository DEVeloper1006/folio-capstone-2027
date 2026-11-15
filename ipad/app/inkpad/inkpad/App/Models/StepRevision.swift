import SwiftData
import Foundation

@Model
final class StepRevision {
    var revisionNumber: Int
    var inkData: Data?
    var strokeFingerprint: String
    var recognizedText: String
    var latex: String
    var statusRaw: String
    var isUserAccepted: Bool = false
    var recognitionProviderRaw: String = ""
    var createdAt: Date
    var step: Step?

    init(
        revisionNumber: Int,
        inkData: Data?,
        strokeFingerprint: String,
        recognizedText: String,
        latex: String,
        status: StepStatus,
        createdAt: Date = Date()
    ) {
        self.revisionNumber = revisionNumber
        self.inkData = inkData
        self.strokeFingerprint = strokeFingerprint
        self.recognizedText = recognizedText
        self.latex = latex
        self.statusRaw = status.rawValue
        self.createdAt = createdAt
    }

    var status: StepStatus {
        get { StepStatus(rawValue: statusRaw) ?? .unchecked }
        set { statusRaw = newValue.rawValue }
    }
}
