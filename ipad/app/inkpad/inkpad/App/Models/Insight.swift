import SwiftData
import Foundation

@Model
final class Insight {
    var title: String
    var detail: String
    var category: String
    var linkedStepIndices: String
    var linkedStepIDs: String = ""
    var severity: String
    var page: Page?

    init(title: String, detail: String, category: String = "arithmetic", linkedStepIndices: String = "", severity: String = "medium") {
        self.title = title
        self.detail = detail
        self.category = category
        self.linkedStepIndices = linkedStepIndices
        self.severity = severity
    }

    var stepIndices: [Int] {
        linkedStepIndices.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    var stepIDs: [UUID] {
        linkedStepIDs.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }
}
