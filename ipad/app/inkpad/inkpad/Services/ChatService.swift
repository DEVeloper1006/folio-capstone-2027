import Foundation

enum SocraticLevel: String, CaseIterable, Identifiable {
    case hint, nudge, explain, solve
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

protocol ChatService {
    func reply(to message: String, level: SocraticLevel, mode: MathMode, context: String?) async -> ChatReply
}

struct ChatReply {
    let text: String
    let latex: String?
    let isRevealPrompt: Bool
    let revealExpected: String?
}

final class MockChatService: ChatService {
    func reply(to message: String, level: SocraticLevel, mode: MathMode, context: String?) async -> ChatReply {
        try? await Task.sleep(for: .seconds(0.8))

        switch level {
        case .hint:
            return ChatReply(
                text: "Think about what happens to row 2 after this operation.",
                latex: nil, isRevealPrompt: false, revealExpected: nil
            )
        case .nudge:
            return ChatReply(
                text: "The entry at position (2,1) should become 0. What value of $k$ in $R_2 \\leftarrow R_2 + kR_1$ makes that happen?",
                latex: "R_2 \\leftarrow R_2 + kR_1", isRevealPrompt: false, revealExpected: nil
            )
        case .explain:
            return ChatReply(
                text: "We apply $R_2 \\leftarrow R_2 + \\frac{3}{2}R_1$ to eliminate the leading entry:\n$$\\begin{bmatrix} 2 & 1 & -1 \\\\ 0 & \\frac{1}{2} & \\frac{1}{2} \\\\ 1 & 1 & 0 \\end{bmatrix}$$\nThe pivot in row 2, column 2 is now $\\frac{1}{2}$.",
                latex: "R_2 \\leftarrow R_2 + \\frac{3}{2}R_1",
                isRevealPrompt: false, revealExpected: nil
            )
        case .solve:
            return ChatReply(
                text: "Applying RREF:\n$$\\begin{bmatrix} 1 & 0 & 0 & | & 3 \\\\ 0 & 1 & 0 & | & 1 \\\\ 0 & 0 & 1 & | & -1 \\end{bmatrix}$$\nSolution: $x=3, y=1, z=-1$.",
                latex: "x=3,\\; y=1,\\; z=-1",
                isRevealPrompt: false, revealExpected: nil
            )
        }
    }
}
