import SwiftUI
import PencilKit

@MainActor
final class NotebookPKCanvasView:PKCanvasView {
    var notebookUndoManager:UndoManager?
    override var undoManager:UndoManager? { notebookUndoManager ?? super.undoManager }
}

struct CanvasView:UIViewRepresentable {
    @Bindable var viewModel:CanvasViewModel
    func makeUIView(context:Context)->NotebookPKCanvasView {
        let canvas=NotebookPKCanvasView()
        canvas.overrideUserInterfaceStyle = .light
        canvas.delegate=context.coordinator
        canvas.drawingPolicy=viewModel.allowFingerDrawing ? .anyInput:.pencilOnly
        canvas.drawing=viewModel.drawing
        canvas.notebookUndoManager=viewModel.history
        canvas.backgroundColor = .clear;canvas.isOpaque=false;canvas.tool=viewModel.pkTool
        canvas.minimumZoomScale=0.5;canvas.maximumZoomScale=4
        canvas.contentSize=CGSize(width:1024,height:max(2048,viewModel.pageHeight.isFinite ? viewModel.pageHeight:2048))
        canvas.showsVerticalScrollIndicator=false
        context.coordinator.attach(canvas)
        viewModel.attach(canvas)
        canvas.becomeFirstResponder()
        canvas.accessibilityIdentifier="notebookInkCanvas"
        context.coordinator.updateAccessibility(canvas)
        return canvas
    }
    func updateUIView(_ canvas:NotebookPKCanvasView,context:Context) {
        canvas.drawingPolicy=viewModel.allowFingerDrawing ? .anyInput:.pencilOnly
        let tool=viewModel.pkTool
        if !toolsMatch(canvas.tool,tool) { canvas.tool=tool }
        if let eraser=canvas.tool as? PKEraserTool {
            canvas.accessibilityLabel="Notebook canvas, eraser, \(Int(eraser.width)) points"
        } else if canvas.tool is PKLassoTool {
            canvas.accessibilityLabel="Notebook canvas, lasso"
        } else { canvas.accessibilityLabel="Notebook canvas, ink" }
        // PencilKit owns the live drawing, selection and undo. Reassigning a
        // snapshot during a SwiftUI refresh can cancel an in-flight edit.
        // Keep PencilKit enabled even while moving a result. The result host
        // receives those touches; disabling the scroll view can cancel ink.
        let requiredHeight=max(viewModel.pageHeight.isFinite ? viewModel.pageHeight:2048,CanvasViewModel.contentHeight(drawing:canvas.drawing))
        if abs(canvas.contentSize.height-requiredHeight*canvas.zoomScale)>1 {
            canvas.contentSize=CGSize(width:1024*canvas.zoomScale,height:requiredHeight*canvas.zoomScale)
        }
        if context.coordinator.focusID != viewModel.focusID,let rect=viewModel.focusRect {
            context.coordinator.focusID=viewModel.focusID
            DispatchQueue.main.async { [weak canvas] in
                guard let canvas else { return }
                let z=canvas.zoomScale
                canvas.scrollRectToVisible(CGRect(x:rect.minX*z,y:rect.minY*z,width:rect.width*z,height:rect.height*z),animated:true)
            }
        }
    }
    static func dismantleUIView(_ uiView:NotebookPKCanvasView,coordinator:Coordinator) { coordinator.viewModel.detach() }
    private func toolsMatch(_ a:PKTool,_ b:PKTool)->Bool {
        if let a=a as? PKInkingTool,let b=b as? PKInkingTool { return a == b }
        if let a=a as? PKEraserTool,let b=b as? PKEraserTool { return a == b }
        return type(of:a)==type(of:b)
    }
    func makeCoordinator()->Coordinator { Coordinator(viewModel:viewModel) }
    final class Coordinator:NSObject,PKCanvasViewDelegate,UIPencilInteractionDelegate {
        let viewModel:CanvasViewModel
        var focusID=UUID()
        private var interaction:UIPencilInteraction?
        private var viewportUpdatePending=false
        init(viewModel:CanvasViewModel) { self.viewModel=viewModel;super.init() }
        func attach(_ canvas:PKCanvasView) {
            let interaction=UIPencilInteraction();interaction.delegate=self;canvas.addInteraction(interaction);self.interaction=interaction
            updateViewport(canvas)
        }
        func canvasViewDidBeginUsingTool(_ canvasView:PKCanvasView) { viewModel.settingsTool=nil }
        func canvasViewDrawingDidChange(_ canvas:PKCanvasView) { updateAccessibility(canvas);viewModel.drawingChanged(canvas.drawing) }
        func updateAccessibility(_ canvas:PKCanvasView) {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--polynomial-ui-test") {
                let image=canvas.drawing.image(from:CGRect(x:0,y:0,width:1024,height:2048),scale:0.25)
                canvas.accessibilityValue="\(canvas.drawing.strokes.count) strokes; \(SpatialInkSegmenter.drawingFingerprint(image.pngData() ?? Data()))"
                return
            }
            #endif
            canvas.accessibilityValue="\(canvas.drawing.strokes.count) strokes"
        }
        func scrollViewDidScroll(_ scrollView:UIScrollView) { updateViewport(scrollView) }
        func scrollViewDidZoom(_ scrollView:UIScrollView) { updateViewport(scrollView) }
        private func updateViewport(_ scroll:UIScrollView) {
            guard !viewportUpdatePending else { return };viewportUpdatePending=true
            DispatchQueue.main.async { [weak self,weak scroll] in
                guard let self else { return };self.viewportUpdatePending=false
                guard let scroll else { return }
                let next=CanvasViewport(offset:scroll.contentOffset,zoom:scroll.zoomScale)
                if self.viewModel.viewport != next { self.viewModel.viewport=next }
            }
        }
        nonisolated func pencilInteractionDidTap(_ interaction:UIPencilInteraction) {
            Task { @MainActor in
                viewModel.handlePencilDoubleTap(UIPencilInteraction.preferredTapAction)
            }
        }
    }
}


struct CanvasPaperBackground:View {
    let style:PageBackgroundStyle
    let viewport:CanvasViewport
    var body:some View {
        Canvas { context,size in
            context.fill(Path(CGRect(origin:.zero,size:size)),with:.color(FolioTheme.paper))
            guard style != .blank else { return }
            let z=max(viewport.zoom,0.01)
            let visible=CGRect(x:viewport.offset.x/z,y:viewport.offset.y/z,width:size.width/z,height:size.height/z)
            context.translateBy(x:-viewport.offset.x,y:-viewport.offset.y);context.scaleBy(x:z,y:z)
            let step:CGFloat=style == .dot ? 28:32
            var y=max(style == .lined ? 80:0,(visible.minY/step).rounded(.down)*step)
            if style == .lined { y=80+max(0,((visible.minY-80)/step).rounded(.down))*step }
            if style == .dot {
                while y<=visible.maxY+step {
                    var x=max(0,(visible.minX/step).rounded(.down)*step)
                    while x<=visible.maxX+step {
                        context.fill(Path(ellipseIn:CGRect(x:x-1.2,y:y-1.2,width:2.4,height:2.4)),with:.color(FolioTheme.canvasGrid));x+=step
                    }
                    y+=step
                }
            } else {
                var path=Path()
                while y<=visible.maxY+step { path.move(to:CGPoint(x:visible.minX,y:y));path.addLine(to:CGPoint(x:visible.maxX,y:y));y+=step }
                if style == .grid {
                    var x=max(0,(visible.minX/step).rounded(.down)*step)
                    while x<=visible.maxX+step { path.move(to:CGPoint(x:x,y:visible.minY));path.addLine(to:CGPoint(x:x,y:visible.maxY));x+=step }
                }
                context.stroke(path,with:.color(FolioTheme.canvasGrid),lineWidth:0.5)
            }
        }.allowsHitTesting(false)
    }
}
