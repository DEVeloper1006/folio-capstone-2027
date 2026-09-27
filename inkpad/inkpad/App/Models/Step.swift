import SwiftData
import Foundation

@Model
final class Step {
    var sortIndex: Int
    var statusRaw: String
    var label: String
    var ghostLaTeX: String
    var explanation: String
    var yPosition: CGFloat
    var page: Page?

    init(sortIndex: Int, status: StepStatus, label: String, ghostLaTeX: String = "", explanation: String = "", yPosition: CGFloat = 0) {
        self.sortIndex = sortIndex
        self.statusRaw = status.rawValue
        self.label = label
        self.ghostLaTeX = ghostLaTeX
        self.explanation = explanation
        self.yPosition = yPosition
    }

    var status: StepStatus {
        get { StepStatus(rawValue: statusRaw) ?? .warning }
        set { statusRaw = newValue.rawValue }
    }
}
