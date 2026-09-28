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

        seedChatThreads(page1: page1, context: context)
        seedInsights(page1: page1, context: context)
        seedClassSpace(context: context)

        try? context.save()
    }

    private static func seedChatThreads(page1: Page, context: ModelContext) {
        let pageThread = ChatThread(title: "Page discussion")
        pageThread.page = page1
        page1.chatThreads.append(pageThread)

        let msg1 = ChatMessage(text: "How do I know which row operation to pick?", isUser: true)
        msg1.thread = pageThread
        pageThread.messages.append(msg1)

        let msg2 = ChatMessage(
            text: "Look at the pivot column. You want to eliminate entries below the pivot. Try $R_2 \\leftarrow R_2 - \\frac{a_{21}}{a_{11}} R_1$.",
            isUser: false,
            latexContent: "R_2 \\leftarrow R_2 - \\frac{a_{21}}{a_{11}} R_1"
        )
        msg2.thread = pageThread
        pageThread.messages.append(msg2)

        let reveal = ChatMessage(
            text: "What should the (2,1) entry be after this row op?",
            isUser: false,
            isRevealCard: true,
            revealMatch: true
        )
        reveal.thread = pageThread
        pageThread.messages.append(reveal)

        let anchoredStep = page1.steps.first { $0.sortIndex == 3 }
        let stepThread = ChatThread(
            title: "Error in R2 − 4·R3",
            anchorStepIndex: 3,
            anchorStepID: anchoredStep?.stableID
        )
        stepThread.page = page1
        page1.chatThreads.append(stepThread)

        let s1 = ChatMessage(text: "Why is step 4 wrong?", isUser: true)
        s1.thread = stepThread
        stepThread.messages.append(s1)

        let s2 = ChatMessage(
            text: "You subtracted $4R_3$ from $R_2$ but used the wrong value for $R_3$'s second entry. Recheck: $R_3 = [0, 2, 1 \\mid 5]$.",
            isUser: false,
            latexContent: "R_3 = [0, 2, 1 \\mid 5]"
        )
        s2.thread = stepThread
        stepThread.messages.append(s2)
    }

    private static func seedInsights(page1: Page, context: ModelContext) {
        let insight1 = Insight(
            title: "Recurring sign error",
            detail: "Steps 3 and 4 both show sign mistakes when subtracting rows. Review the subtraction of negative entries.",
            category: "arithmetic",
            linkedStepIndices: "2,3",
            severity: "high"
        )
        insight1.page = page1
        insight1.linkedStepIDs = page1.steps
            .filter { [2, 3].contains($0.sortIndex) }
            .map { $0.stableID.uuidString }
            .joined(separator: ",")
        page1.insights.append(insight1)

        let insight2 = Insight(
            title: "Pivot selection",
            detail: "Consider using partial pivoting to avoid small pivots that amplify rounding errors.",
            category: "strategy",
            linkedStepIndices: "0",
            severity: "medium"
        )
        insight2.page = page1
        insight2.linkedStepIDs = page1.steps
            .filter { $0.sortIndex == 0 }
            .map { $0.stableID.uuidString }
            .joined(separator: ",")
        page1.insights.append(insight2)
    }

    private static func seedClassSpace(context: ModelContext) {
        let classSpace = ClassSpace(name: "Linear Algebra", courseCode: "MATH 2LA3", instructorName: "Dr. Rivera")
        context.insert(classSpace)

        let ex1 = WorkedExample(
            title: "Row Reduction to RREF",
            detail: "Reduce a 3×3 augmented matrix to RREF using elementary row operations.",
            mathMode: .linalg,
            stepsJSON: "[\"Form augmented matrix\",\"Eliminate below pivot 1\",\"Eliminate below pivot 2\",\"Back-substitute\"]"
        )
        ex1.classSpace = classSpace
        classSpace.workedExamples.append(ex1)

        let ex2 = WorkedExample(
            title: "Determinant via Cofactor Expansion",
            detail: "Compute the determinant of a 3×3 matrix using cofactor expansion along the first row.",
            mathMode: .linalg,
            stepsJSON: "[\"Write 3×3 matrix\",\"Expand along row 1\",\"Compute 2×2 minors\",\"Combine with signs\"]"
        )
        ex2.classSpace = classSpace
        classSpace.workedExamples.append(ex2)
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
