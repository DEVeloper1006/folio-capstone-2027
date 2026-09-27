import SwiftUI
import PencilKit

@Observable
final class CanvasViewModel {
    var drawing: PKDrawing
    var backgroundStyle: PageBackgroundStyle
    var allowFingerDrawing: Bool = false

    private var autosaveTask: Task<Void, Never>?
    var onSave: ((Data, PageBackgroundStyle) -> Void)?

    init(drawingData: Data? = nil, backgroundStyle: PageBackgroundStyle = .blank) {
        self.drawing = (drawingData.flatMap { try? PKDrawing(data: $0) }) ?? PKDrawing()
        self.backgroundStyle = backgroundStyle
    }

    func drawingChanged(_ newDrawing: PKDrawing) {
        drawing = newDrawing
        scheduleAutosave()
    }

    func save() {
        autosaveTask?.cancel()
        onSave?(drawing.dataRepresentation(), backgroundStyle)
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
