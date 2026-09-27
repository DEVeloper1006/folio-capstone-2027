import SwiftData
import Foundation

@Model
final class ChatThread {
    var title: String
    var anchorStepIndex: Int?
    var anchorSelectionRect: String?
    var createdAt: Date
    var page: Page?
    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.thread)
    var messages: [ChatMessage]

    init(title: String, anchorStepIndex: Int? = nil) {
        self.title = title
        self.anchorStepIndex = anchorStepIndex
        self.createdAt = Date()
        self.messages = []
    }

    var isPageThread: Bool { anchorStepIndex == nil && anchorSelectionRect == nil }
}
