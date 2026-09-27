import SwiftData
import Foundation

@Model
final class Page {
    var sortIndex: Int
    var drawingData: Data?
    var backgroundStyle: String
    var mathModeRaw: String
    var notebook: Notebook?
    @Relationship(deleteRule: .cascade, inverse: \Step.page)
    var steps: [Step]
    @Relationship(deleteRule: .cascade, inverse: \Branch.page)
    var branches: [Branch]

    init(sortIndex: Int, backgroundStyle: PageBackgroundStyle = .dot, mathMode: MathMode = .linalg) {
        self.sortIndex = sortIndex
        self.drawingData = nil
        self.backgroundStyle = backgroundStyle.rawValue
        self.mathModeRaw = mathMode.rawValue
        self.steps = []
        self.branches = []
    }

    var background: PageBackgroundStyle {
        get { PageBackgroundStyle(rawValue: backgroundStyle) ?? .dot }
        set { backgroundStyle = newValue.rawValue }
    }

    var mathMode: MathMode {
        get { MathMode(rawValue: mathModeRaw) ?? .linalg }
        set { mathModeRaw = newValue.rawValue }
    }
}
