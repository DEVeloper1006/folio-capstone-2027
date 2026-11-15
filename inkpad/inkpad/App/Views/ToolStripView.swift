import SwiftUI
import PencilKit

struct ToolStripView:View {
    @Bindable var viewModel:CanvasViewModel
    var body:some View {
        HStack(spacing:4) {
            ForEach(DrawingTool.allCases) { tool in
                Button {
                    viewModel.tapToolbarTool(tool)
                } label: {
                    Image(systemName:tool.icon).font(.system(size:17,weight:.medium)).frame(width:36,height:36)
                        .background(viewModel.currentTool == tool ? FolioTheme.panelSecondary:Color.clear,in:RoundedRectangle(cornerRadius:8))
                }
                .accessibilityLabel(tool.label).accessibilityIdentifier("tool-"+tool.rawValue)
                .foregroundStyle(viewModel.currentTool == tool ? FolioTheme.ink:FolioTheme.muted)

            }
            Divider().frame(height:24).padding(.horizontal,4)
            ForEach(InkColor.allCases) { ink in
                Button { viewModel.inkColor=ink.color } label: {
                    Circle().fill(ink.color).frame(width:22,height:22)
                        .overlay(Circle().strokeBorder(FolioTheme.ink,lineWidth:viewModel.matchesInk(ink.uiColor) ? 2:0).frame(width:26,height:26))
                }.frame(width:32,height:36).accessibilityLabel(ink.rawValue.capitalized+" ink").accessibilityIdentifier("ink-"+ink.rawValue)
            }
            ColorPicker("Ink colour",selection:$viewModel.inkColor,supportsOpacity:false).labelsHidden().frame(width:32,height:36)
                .accessibilityLabel("Choose any ink colour").accessibilityIdentifier("inkColourPicker")
            Divider().frame(height:24).padding(.horizontal,4)
            Button { viewModel.undo() } label: { Image(systemName:"arrow.uturn.backward").frame(width:28,height:36) }
                .disabled(!viewModel.canUndo).accessibilityLabel("Undo").accessibilityIdentifier("undoCanvas")
            Button { viewModel.redo() } label: { Image(systemName:"arrow.uturn.forward").frame(width:28,height:36) }
                .disabled(!viewModel.canRedo).accessibilityLabel("Redo").accessibilityIdentifier("redoCanvas")
        }.padding(.horizontal,12).padding(.vertical,6)
            .foregroundStyle(FolioTheme.ink)
            .background(Capsule().fill(FolioTheme.chromeBackground).shadow(color:FolioTheme.chromeShadow,radius:8,y:2))
    }
}

// Nonmodal: unlike a popover, this never consumes the first Pencil stroke
// on the page while dismissing tool settings.
struct CanvasToolOptions:View {
    @Bindable var viewModel:CanvasViewModel
    let tool:DrawingTool
    var body:some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text(tool.label).font(.headline)
                Spacer()
                Button("Done") { viewModel.settingsTool=nil }
            }
            if tool != .lasso {
                Text(String(format:"%.1f pt",Double(viewModel.width(for:tool))))
                    .monospacedDigit().accessibilityIdentifier("thicknessValue")
                Slider(value:Binding(get:{viewModel.width(for:tool)},set:{viewModel.setWidth($0,for:tool)}),in:tool.widthRange)
                    .accessibilityLabel(tool.label+" thickness").accessibilityIdentifier("toolThickness")
            } else {
                Text("Circle ink to select it, then drag the selection. Drag a result card to move the whole result.")
                    .font(.caption)
            }
            Toggle("Draw with finger",isOn:$viewModel.allowFingerDrawing)
                .accessibilityIdentifier("fingerDrawing")
        }
        .padding().frame(width:280)
        .foregroundStyle(FolioTheme.ink)
        .background(FolioTheme.chromeBackground,in:RoundedRectangle(cornerRadius:12))
        .overlay(RoundedRectangle(cornerRadius:12).stroke(FolioTheme.muted.opacity(0.3)))
        .shadow(radius:5,y:2)
    }
}
