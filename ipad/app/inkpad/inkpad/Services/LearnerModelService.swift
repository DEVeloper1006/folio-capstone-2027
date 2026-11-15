import Foundation

struct InsightData: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let category: String
    let linkedStepIndices: [Int]
    let severity: InsightSeverity
}

enum InsightSeverity: String {
    case low, medium, high
}

protocol LearnerModelService {
    func insights(for stepLabels: [String], mode: MathMode) -> [InsightData]
    func confidence(for stepIndex: Int) -> Int?
}

final class MockLearnerModelService: LearnerModelService {
    func insights(for stepLabels: [String], mode: MathMode) -> [InsightData] {
        [
            InsightData(
                title: "Sign error in row operations",
                detail: "You've made sign errors in 2 of 4 row operations. Double-check subtraction when combining rows.",
                category: "arithmetic",
                linkedStepIndices: [2, 3],
                severity: .high
            ),
            InsightData(
                title: "Pivot selection",
                detail: "Consider choosing the largest absolute value as pivot to reduce rounding errors.",
                category: "strategy",
                linkedStepIndices: [1],
                severity: .low
            ),
        ]
    }

    func confidence(for stepIndex: Int) -> Int? {
        [0: 3, 1: 2, 2: 1, 3: nil][stepIndex] ?? nil
    }
}
