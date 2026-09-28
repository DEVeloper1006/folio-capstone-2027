import SwiftData
import Foundation
import CoreGraphics

@Model
final class Step {
    var stableID: UUID = UUID()
    var sortIndex: Int
    var statusRaw: String
    var label: String
    var ghostLaTeX: String
    var explanation: String
    var yPosition: CGFloat
    var inkData: Data?
    var boundsX: Double = 0
    var boundsY: Double = 0
    var boundsWidth: Double = 0
    var boundsHeight: Double = 0
    var strokeFingerprint: String = ""
    var recognizedText: String = ""
    var recognitionConfidence: Double = 0
    var recognitionStateRaw: String = "ready"
    var sourceRaw: String = "seeded"
    var isActive: Bool = true
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var page: Page?
    @Relationship(deleteRule: .cascade, inverse: \StepRevision.step)
    var revisions: [StepRevision] = []

    init(
        sortIndex: Int,
        status: StepStatus,
        label: String,
        ghostLaTeX: String = "",
        explanation: String = "",
        yPosition: CGFloat = 0,
        source: StepSource = .seeded
    ) {
        self.sortIndex = sortIndex
        self.statusRaw = status.rawValue
        self.label = label
        self.ghostLaTeX = ghostLaTeX
        self.explanation = explanation
        self.yPosition = yPosition
        self.sourceRaw = source.rawValue
    }

    var status: StepStatus {
        get { StepStatus(rawValue: statusRaw) ?? .unchecked }
        set { statusRaw = newValue.rawValue }
    }

    var recognitionState: StepRecognitionState {
        get { StepRecognitionState(rawValue: recognitionStateRaw) ?? .ready }
        set { recognitionStateRaw = newValue.rawValue }
    }

    var source: StepSource {
        get { StepSource(rawValue: sourceRaw) ?? .seeded }
        set { sourceRaw = newValue.rawValue }
    }

    var bounds: CGRect {
        get { CGRect(x: boundsX, y: boundsY, width: boundsWidth, height: boundsHeight) }
        set {
            boundsX = newValue.origin.x
            boundsY = newValue.origin.y
            boundsWidth = newValue.width
            boundsHeight = newValue.height
            yPosition = newValue.minY
        }
    }
}

enum StepRecognitionState: String, Codable {
    case collecting, recognizing, ready, ambiguous, failed
}

enum StepSource: String, Codable {
    case seeded, manual, inferred
}
