import SwiftData
import Foundation

@Model
final class ChatThread {
    var title: String
    var anchorStepIndex: Int?
    var anchorStepID: UUID?
    var anchorSelectionRect: String?
    var createdAt: Date
    var page: Page?
    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.thread)
    var messages: [ChatMessage]

    init(title: String, anchorStepIndex: Int? = nil, anchorStepID: UUID? = nil) {
        self.title = title
        self.anchorStepIndex = anchorStepIndex
        self.anchorStepID = anchorStepID
        self.createdAt = Date()
        self.messages = []
    }

    var isPageThread: Bool { anchorStepID == nil && anchorStepIndex == nil && anchorSelectionRect == nil }
}
