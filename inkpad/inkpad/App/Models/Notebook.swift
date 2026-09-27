import SwiftData
import Foundation

@Model
final class Notebook {
    var name: String
    var createdAt: Date
    @Relationship(deleteRule: .cascade, inverse: \Page.notebook)
    var pages: [Page]

    init(name: String) {
        self.name = name
        self.createdAt = Date()
        self.pages = []
    }
}
