import SwiftData
import Foundation

@Model
final class Branch {
    var name: String
    var sortIndex: Int
    var statusRaw: String
    var thumbnailData: Data?
    var drawingData: Data?
    var page: Page?

    init(name: String, sortIndex: Int, status: StepStatus = .warning) {
        self.name = name
        self.sortIndex = sortIndex
        self.statusRaw = status.rawValue
    }

    var status: StepStatus {
        get { StepStatus(rawValue: statusRaw) ?? .warning }
        set { statusRaw = newValue.rawValue }
    }
}
