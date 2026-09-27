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

        let toolPicker = PKToolPicker()
        context.coordinator.toolPicker = toolPicker

        DispatchQueue.main.async {
            toolPicker.setVisible(true, forFirstResponder: canvasView)
            toolPicker.addObserver(canvasView)
            canvasView.becomeFirstResponder()
        }

        return canvasView
    }

    func updateUIView(_ canvasView: PKCanvasView, context: Context) {
        if viewModel.allowFingerDrawing {
            canvasView.drawingPolicy = .anyInput
        } else {
            canvasView.drawingPolicy = .pencilOnly
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        let viewModel: CanvasViewModel
        var toolPicker: PKToolPicker?

        init(viewModel: CanvasViewModel) {
            self.viewModel = viewModel
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            viewModel.drawingChanged(canvasView.drawing)
        }
    }
}
