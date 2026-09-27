import Foundation

protocol ClassService {
    func availableClasses() -> [ClassInfo]
    func workedExamples(for classId: String) -> [WorkedExampleInfo]
}

struct ClassInfo: Identifiable {
    let id: String
    let name: String
    let courseCode: String
    let instructor: String
    let exampleCount: Int
}

struct WorkedExampleInfo: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let mathMode: MathMode
    let stepsPreview: [String]
}

final class MockClassService: ClassService {
    func availableClasses() -> [ClassInfo] {
        [
            ClassInfo(id: "stats2d03", name: "Intro to Statistics", courseCode: "STATS 2D03", instructor: "Dr. Chen", exampleCount: 2)
        ]
    }

    func workedExamples(for classId: String) -> [WorkedExampleInfo] {
        [
            WorkedExampleInfo(
                title: "Solving a 3×3 System",
                detail: "Row reduction to RREF with back-substitution",
                mathMode: .linalg,
                stepsPreview: ["\\begin{bmatrix} 2 & 1 & -1 \\\\ -3 & -1 & 2 \\\\ -2 & 1 & 2 \\end{bmatrix}", "R_2 \\leftarrow R_2 + \\frac{3}{2}R_1"]
            ),
            WorkedExampleInfo(
                title: "Integration by Parts",
                detail: "Evaluating ∫x²eˣ dx step by step",
                mathMode: .calc,
                stepsPreview: ["\\int x^2 e^x \\, dx", "u = x^2,\\; dv = e^x\\,dx"]
            ),
        ]
    }
}
