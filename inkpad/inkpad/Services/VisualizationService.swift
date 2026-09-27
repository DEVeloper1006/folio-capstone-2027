import Foundation

enum VisualizeCardType: String, CaseIterable {
    case graph, vector2D, matrixHeatmap
    var label: String {
        switch self {
        case .graph: "Graph"
        case .vector2D: "2D Vectors"
        case .matrixHeatmap: "Matrix Heatmap"
        }
    }
    var icon: String {
        switch self {
        case .graph: "chart.xyaxis.line"
        case .vector2D: "arrow.up.right"
        case .matrixHeatmap: "square.grid.3x3.fill"
        }
    }
}

struct VisualizeData: Identifiable {
    let id = UUID()
    let type: VisualizeCardType
    let stepIndex: Int
    let title: String
    let graphPoints: [(x: Double, y: Double)]
    let vectors: [(dx: Double, dy: Double)]
    let matrixValues: [[Double]]
}

protocol VisualizationService {
    func visualize(stepLabel: String, mode: MathMode) -> VisualizeData
}

final class MockVisualizationService: VisualizationService {
    func visualize(stepLabel: String, mode: MathMode) -> VisualizeData {
        switch mode {
        case .linalg:
            return VisualizeData(
                type: .matrixHeatmap, stepIndex: 0,
                title: "Augmented Matrix",
                graphPoints: [],
                vectors: [(2, 1), (-3, -1), (-2, 1)],
                matrixValues: [[2, 1, -1], [-3, -1, 2], [-2, 1, 2]]
            )
        case .calc:
            return VisualizeData(
                type: .graph, stepIndex: 0,
                title: "f(x) = x²eˣ",
                graphPoints: stride(from: -2.0, through: 2.0, by: 0.2).map { ($0, $0 * $0 * exp($0)) },
                vectors: [], matrixValues: []
            )
        case .proof:
            return VisualizeData(
                type: .vector2D, stepIndex: 0,
                title: "Number Line",
                graphPoints: [],
                vectors: [(1.414, 0)], matrixValues: []
            )
        }
    }
}
