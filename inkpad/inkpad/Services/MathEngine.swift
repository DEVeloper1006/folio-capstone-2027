import Foundation

protocol MathEngine {
    func checkStep(latex: String, mode: MathMode) -> StepStatus
    func hint(for latex: String, mode: MathMode) -> String
    func explain(latex: String, mode: MathMode) -> String
    func formalize(latex: String, mode: MathMode) -> String
}

final class MockMathEngine: MathEngine {
    func checkStep(latex: String, mode: MathMode) -> StepStatus {
        if latex.contains("error") || latex.contains("wrong") { return .error }
        if latex.contains("R3") || latex.contains("warn") { return .warning }
        return .verified
    }

    func hint(for latex: String, mode: MathMode) -> String {
        switch mode {
        case .linalg: "What's row 2's first entry now?"
        case .calc: "Try u-substitution with u = x²."
        case .proof: "Consider the contrapositive."
        }
    }

    func explain(latex: String, mode: MathMode) -> String {
        switch mode {
        case .linalg: "This row operation eliminates the leading entry in row 2."
        case .calc: "Apply the power rule: d/dx(xⁿ) = nxⁿ⁻¹."
        case .proof: "This follows from the definition of divisibility."
        }
    }

    func formalize(latex: String, mode: MathMode) -> String {
        "\\text{Formalized: } \(latex)"
    }
}
