import SwiftData
import Foundation

@Model
final class ChatMessage {
    var text: String
    var isUser: Bool
    var timestamp: Date
    var latexContent: String?
    var isRevealCard: Bool
    var revealMatch: Bool?
    var thread: ChatThread?

    init(text: String, isUser: Bool, latexContent: String? = nil, isRevealCard: Bool = false, revealMatch: Bool? = nil) {
        self.text = text
        self.isUser = isUser
        self.timestamp = Date()
        self.latexContent = latexContent
        self.isRevealCard = isRevealCard
        self.revealMatch = revealMatch
    }
}
