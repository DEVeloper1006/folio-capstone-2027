import SwiftData
import Foundation

@Model
final class Snapshot {
    var name: String
    var drawingData: Data?
    var createdAt: Date
    var page: Page?

    init(name: String, drawingData: Data? = nil) {
        self.name = name
        self.drawingData = drawingData
        self.createdAt = Date()
    }
}
