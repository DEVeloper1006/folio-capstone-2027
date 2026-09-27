import SwiftUI
import PencilKit

struct CanvasView: UIViewRepresentable {
    var viewModel: CanvasViewModel

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.delegate = context.coordinator
        canvasView.drawingPolicy = viewModel.allowFingerDrawing ? .anyInput : .pencilOnly
        canvasView.drawing = viewModel.drawing
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.tool = viewModel.pkTool
        canvasView.minimumZoomScale = 0.5
        canvasView.maximumZoomScale = 4.0
        canvasView.contentSize = CGSize(width: 1024, height: 2048)
        canvasView.showsVerticalScrollIndicator = false

        context.coordinator.canvasView = canvasView
        canvasView.becomeFirstResponder()
        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        canvasView.drawingPolicy = viewModel.allowFingerDrawing ? .anyInput : .pencilOnly
        let newTool = viewModel.pkTool
        if type(of: canvasView.tool) != type(of: newTool) || !toolsMatch(canvasView.tool, newTool) {
            canvasView.tool = newTool
        }
    }

    private func toolsMatch(_ a: PKTool, _ b: PKTool) -> Bool {
        if let ai = a as? PKInkingTool, let bi = b as? PKInkingTool {
            return ai.inkType == bi.inkType && ai.color == bi.color && ai.width == bi.width
        }
        return type(of: a) == type(of: b)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIPencilInteractionDelegate {
        let viewModel: CanvasViewModel
        weak var canvasView: PKCanvasView?
        private var pencilInteraction: UIPencilInteraction?

        init(viewModel: CanvasViewModel) {
            self.viewModel = viewModel
            super.init()

            let interaction = UIPencilInteraction()
            interaction.delegate = self
            self.pencilInteraction = interaction
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            viewModel.drawingChanged(canvasView.drawing)
        }

        nonisolated func pencilInteractionDidTap(_ interaction: UIPencilInteraction) {
            Task { @MainActor in
                if viewModel.currentTool == .eraser {
                    viewModel.currentTool = .pen
                } else {
                    viewModel.currentTool = .eraser
                }
            }
        }
    }
}
