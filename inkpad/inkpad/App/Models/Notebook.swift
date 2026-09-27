import SwiftData
import Foundation

@Model
final class Notebook {
    var name: String
    var createdAt: Date
    var lastEditedAt: Date
    var coverColorIndex: Int
    var mathModeRaw: String
    @Relationship(deleteRule: .cascade, inverse: \Page.notebook)
    var pages: [Page]

    init(name: String, mathMode: MathMode = .linalg, coverColorIndex: Int = 0) {
        self.name = name
        self.createdAt = Date()
        self.lastEditedAt = Date()
        self.coverColorIndex = coverColorIndex
        self.mathModeRaw = mathMode.rawValue
        self.pages = []
    }

    var mathMode: MathMode {
        get { MathMode(rawValue: mathModeRaw) ?? .linalg }
        set { mathModeRaw = newValue.rawValue }
    }
}
