import SwiftUI
import PencilKit

enum DrawingTool: String, CaseIterable, Identifiable {
    case pen, highlighter, eraser, lasso

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pen: "Pen"
        case .highlighter: "Highlighter"
        case .eraser: "Eraser"
        case .lasso: "Lasso"
        }
    }

    var icon: String {
        switch self {
        case .pen: "pencil.tip"
        case .highlighter: "highlighter"
        case .eraser: "eraser"
        case .lasso: "lasso"
        }
    }
}

enum InkColor: String, CaseIterable, Identifiable {
    case graphite, blue, red

    var id: String { rawValue }

    var uiColor: UIColor {
        switch self {
        case .graphite: UIColor(red: 0.11, green: 0.11, blue: 0.10, alpha: 1)
        case .blue: UIColor(red: 0.20, green: 0.40, blue: 0.72, alpha: 1)
        case .red: UIColor(red: 0.75, green: 0.25, blue: 0.22, alpha: 1)
        }
    }

    var color: Color { Color(uiColor: uiColor) }
}

@Observable
final class CanvasViewModel {
    var drawing: PKDrawing
    var backgroundStyle: PageBackgroundStyle
    #if targetEnvironment(simulator)
    var allowFingerDrawing: Bool = true
    #else
    var allowFingerDrawing: Bool = false
    #endif

    var currentTool: DrawingTool = .pen
    var currentColor: InkColor = .graphite
    var penWidth: CGFloat = 2.0
    var highlighterWidth: CGFloat = 15.0

    var sessionMode: SessionMode = .coach
    var mathMode: MathMode = .linalg

    var showTypeset: Bool = true

    var selectedStrokesBounds: CGRect? = nil
    var showRadialMenu: Bool = false

    private var autosaveTask: Task<Void, Never>?
    var onSave: ((Data, PageBackgroundStyle) -> Void)?

    init(drawingData: Data? = nil, backgroundStyle: PageBackgroundStyle = .dot, mathMode: MathMode = .linalg) {
        self.drawing = (drawingData.flatMap { try? PKDrawing(data: $0) }) ?? PKDrawing()
        self.backgroundStyle = backgroundStyle
        self.mathMode = mathMode
    }

    var pkTool: PKTool {
        switch currentTool {
        case .pen:
            PKInkingTool(.pen, color: currentColor.uiColor, width: penWidth)
        case .highlighter:
            PKInkingTool(.marker, color: currentColor.uiColor.withAlphaComponent(0.3), width: highlighterWidth)
        case .eraser:
            PKEraserTool(.bitmap)
        case .lasso:
            PKLassoTool()
        }
    }

    func drawingChanged(_ newDrawing: PKDrawing) {
        drawing = newDrawing
        scheduleAutosave()
    }

    func save() {
        autosaveTask?.cancel()
        onSave?(drawing.dataRepresentation(), backgroundStyle)
    }

    func toggleTool(to tool: DrawingTool) {
        if currentTool == tool && tool == .eraser {
            currentTool = .pen
        } else {
            currentTool = tool
        }
        if tool != .lasso {
            selectedStrokesBounds = nil
            showRadialMenu = false
        }
    }

    func cycleMathMode() {
        mathMode = mathMode.next
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            save()
        }
    }
}
