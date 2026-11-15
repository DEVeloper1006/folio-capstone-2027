import SwiftData
import Foundation

@Model
final class WorkedExample {
    var title: String
    var detail: String
    var mathModeRaw: String
    var stepsJSON: String
    var isPublished: Bool
    var classSpace: ClassSpace?

    init(title: String, detail: String = "", mathMode: MathMode = .linalg, stepsJSON: String = "[]", isPublished: Bool = true) {
        self.title = title
        self.detail = detail
        self.mathModeRaw = mathMode.rawValue
        self.stepsJSON = stepsJSON
        self.isPublished = isPublished
    }

    var mathMode: MathMode {
        get { MathMode(rawValue: mathModeRaw) ?? .linalg }
        set { mathModeRaw = newValue.rawValue }
    }
}
