import SwiftData
import Foundation

enum SeedDataBuilder {
    static func seed(into context: ModelContext) {
        let ps1 = Notebook(name: "Problem Set 1", mathMode: .linalg, coverColorIndex: 0)
        context.insert(ps1)

        let page1 = buildLinalgPage()
        page1.notebook = ps1
        ps1.pages.append(page1)

        let page2 = buildCalculusPage()
        page2.notebook = ps1
        ps1.pages.append(page2)

        let page3 = buildProofPage()
        page3.notebook = ps1
        ps1.pages.append(page3)

        try? context.save()
    }

    private static func buildLinalgPage() -> Page {
        let page = Page(sortIndex: 0, backgroundStyle: .dot, mathMode: .linalg)

        let steps: [(Int, StepStatus, String, String, String, CGFloat)] = [
            (0, .verified, "Augmented matrix",
             "2x + y - z = 8",
             "The augmented matrix is correctly formed.", 140),
            (1, .verified, "R2 → R2 + 1.5·R1",
             "R₂ ← R₂ + 1.5R₁",
             "Row operation applied correctly. Row 2 is now [0, 0.5, 0.5 | 1].", 360),
            (2, .warning, "R3 → R3 + R1",
             "R₃ ← R₃ + R₁",
             "Check: the coefficient in column 2 should be 2, not 1.", 510),
            (3, .error, "R2 → R2 − 4·R3",
             "R₂ ← R₂ − 4R₃",
             "Error in arithmetic: row 2 result does not match expected values.", 650),
        ]

        for (i, status, label, ghost, explanation, y) in steps {
            let step = Step(sortIndex: i, status: status, label: label, ghostLaTeX: ghost, explanation: explanation, yPosition: y)
            step.page = page
            page.steps.append(step)
        }

        let branch = Branch(name: "Alternative pivot", sortIndex: 0, status: .warning)
        branch.page = page
        page.branches.append(branch)

        return page
    }

    private static func buildCalculusPage() -> Page {
        let page = Page(sortIndex: 1, backgroundStyle: .dot, mathMode: .calc)

        let steps: [(Int, StepStatus, String, String, String, CGFloat)] = [
            (0, .verified, "f(x) = x²eˣ",
             "f(x) = x^2 e^x",
             "Function defined correctly.", 140),
            (1, .verified, "Integration by parts",
             "\\int x^2 e^x \\, dx",
             "Correct setup for integration by parts.", 300),
            (2, .warning, "u = x², dv = eˣdx",
             "u = x^2, \\; dv = e^x \\, dx",
             "Good choice of u and dv. Continue with the formula.", 420),
        ]

        for (i, status, label, ghost, explanation, y) in steps {
            let step = Step(sortIndex: i, status: status, label: label, ghostLaTeX: ghost, explanation: explanation, yPosition: y)
            step.page = page
            page.steps.append(step)
        }

        return page
    }

    private static func buildProofPage() -> Page {
        let page = Page(sortIndex: 2, backgroundStyle: .dot, mathMode: .proof)

        let steps: [(Int, StepStatus, String, String, String, CGFloat)] = [
            (0, .verified, "Theorem: √2 is irrational",
             "\\text{Theorem: } \\sqrt{2} \\text{ is irrational}",
             "Theorem statement is clear.", 140),
            (1, .verified, "Assume √2 = a/b",
             "\\text{Assume } \\sqrt{2} = a/b, \\; \\gcd(a,b) = 1",
             "Proof by contradiction setup is correct.", 280),
            (2, .warning, "Then 2 = a²/b²",
             "2 = a^2 / b^2 \\implies 2b^2 = a^2",
             "Correct step. Continue to show a must be even.", 400),
        ]

        for (i, status, label, ghost, explanation, y) in steps {
            let step = Step(sortIndex: i, status: status, label: label, ghostLaTeX: ghost, explanation: explanation, yPosition: y)
            step.page = page
            page.steps.append(step)
        }

        return page
    }
}
