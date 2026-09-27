import SwiftUI
import PencilKit

struct ToolStripView: View {
    @Bindable var viewModel: CanvasViewModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DrawingTool.allCases) { tool in
                toolButton(tool)
            }

            Divider().frame(height: 24).padding(.horizontal, 4)

            ForEach(InkColor.allCases) { ink in
                inkSwatch(ink)
            }

            widthPicker

            Divider().frame(height: 24).padding(.horizontal, 4)

            Button { viewModel.drawing = undoDrawing() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(FolioTheme.ink)
            .disabled(true)

            Button { } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(FolioTheme.ink)
            .disabled(true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(FolioTheme.chromeBackground)
                .shadow(color: FolioTheme.chromeShadow, radius: 8, y: 2)
        )
    }

    private func toolButton(_ tool: DrawingTool) -> some View {
        Button {
            viewModel.toggleTool(to: tool)
        } label: {
            Image(systemName: tool.icon)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 36, height: 36)
                .background(
                    viewModel.currentTool == tool
                    ? FolioTheme.panelSecondary
                    : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .foregroundStyle(viewModel.currentTool == tool ? FolioTheme.ink : FolioTheme.muted)
    }

    private func inkSwatch(_ ink: InkColor) -> some View {
        Button {
            viewModel.currentColor = ink
        } label: {
            Circle()
                .fill(ink.color)
                .frame(width: 22, height: 22)
                .overlay(
                    Circle()
                        .strokeBorder(FolioTheme.ink, lineWidth: viewModel.currentColor == ink ? 2 : 0)
                        .frame(width: 26, height: 26)
                )
        }
        .frame(width: 32, height: 36)
    }

    private var widthPicker: some View {
        Menu {
            ForEach([1.0, 2.0, 4.0, 6.0], id: \.self) { width in
                Button {
                    viewModel.penWidth = width
                } label: {
                    Label(
                        width == 1 ? "Fine" : width == 2 ? "Medium" : width == 4 ? "Thick" : "Bold",
                        systemImage: "circle.fill"
                    )
                }
            }
        } label: {
            Image(systemName: "lineweight")
                .font(.system(size: 15, weight: .medium))
                .frame(width: 36, height: 36)
        }
        .foregroundStyle(FolioTheme.muted)
    }

    private func undoDrawing() -> PKDrawing {
        viewModel.drawing
    }
}
