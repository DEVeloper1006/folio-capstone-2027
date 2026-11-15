import SwiftUI
import SwiftData

struct CanvasResultLayer:View {
    let page:Page
    @Bindable var viewModel:CanvasViewModel
    @Query(filter: #Predicate<ComputationResult> { $0.isPlacedOnCanvas && !$0.isRemoved }) private var placed: [ComputationResult]
    var body:some View {
        let results=placed.filter { $0.source?.page?.persistentModelID == page.persistentModelID }
        ResultOverlayHost(results:results,viewModel:viewModel)
    }
}

// Only actual result rectangles receive touches, with any active tool. Blank
// canvas areas always pass through to native PencilKit for writing/selection.
@MainActor
final class ResultHitTestView:UIView {
    var interactiveRects:[CGRect]=[]
    override func hitTest(_ point:CGPoint,with event:UIEvent?)->UIView? {
        guard interactiveRects.contains(where: { $0.contains(point) }) else { return nil }
        return super.hitTest(point,with:event)
    }
}

private struct ResultOverlayHost:UIViewRepresentable {
    let results:[ComputationResult]
    @Bindable var viewModel:CanvasViewModel
    func makeCoordinator()->Coordinator { Coordinator() }
    func makeUIView(context:Context)->ResultHitTestView {
        let view=ResultHitTestView();view.backgroundColor = .clear
        let host=UIHostingController(rootView:ResultOverlayContent(results:results,viewModel:viewModel))
        context.coordinator.host=host
        host.view.backgroundColor = .clear;host.view.translatesAutoresizingMaskIntoConstraints=false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo:view.leadingAnchor),host.view.trailingAnchor.constraint(equalTo:view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo:view.topAnchor),host.view.bottomAnchor.constraint(equalTo:view.bottomAnchor)
        ])
        return view
    }
    @Environment(\.modelContext) private var modelContext
    func updateUIView(_ view:ResultHitTestView,context:Context) {
        // A hosting controller creates a new environment; explicitly carry the
        // notebook's SwiftData context across for save/undo operations.
        context.coordinator.host?.rootView=ResultOverlayContent(results:results,viewModel:viewModel)
        context.coordinator.host?.rootView.context=modelContext
        let viewport=viewModel.viewport
        view.interactiveRects=results.map {
            CGRect(origin:viewport.displayPoint($0.canvasRect.origin),size:CGSize(width:$0.canvasWidth*viewport.zoom,height:$0.canvasHeight*viewport.zoom))
        }
    }
    final class Coordinator {
        var host:UIHostingController<ResultOverlayContent>?
    }
}

private struct ResultOverlayContent:View {
    let results:[ComputationResult]
    @Bindable var viewModel:CanvasViewModel
    var context:ModelContext?
    var body:some View {
        ZStack(alignment:.topLeading) {
            ForEach(results,id:\.stableID) { result in
                if let context {
                    MovableCanvasResult(result:result,viewModel:viewModel).environment(\.modelContext,context)
                }
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .coordinateSpace(name:"notebookPageViewport").clipped()
    }
}

private struct MovableCanvasResult:View {
    @Environment(\.modelContext) private var context
    let result:ComputationResult
    @Bindable var viewModel:CanvasViewModel
    @State private var translation:CGSize = .zero
    @State private var start:CGPoint?
    @State private var dragZoom:CGFloat=1
    var body:some View {
        VStack(spacing:0) {
            HStack {
                Image(systemName:"arrow.up.and.down.and.arrow.left.and.right")
                Text(result.isCurrent ? "Result · drag":"Outdated · drag").font(.caption)
                Spacer()
                Button {
                    do { try CanvasResultStore.removeFromCanvas(result,context:context,history:viewModel.history,onError:report) }
                    catch { report(error.localizedDescription) }
                } label: { Image(systemName:"xmark.circle.fill") }.accessibilityLabel("Remove result from page")
            }.padding(8).background(result.isCurrent ? Color.gray.opacity(0.1):Color.orange.opacity(0.18))
            if let data=result.canvasPreviewPNG,let image=UIImage(data:data) {
                let pixels=CGSize(width:CGFloat(image.cgImage?.width ?? 0),height:CGFloat(image.cgImage?.height ?? 0))
                let size=CanvasResultLayout.displaySize(pixels:pixels,available:CGSize(width:max(1,result.canvasWidth-20),height:max(1,result.canvasHeight-56)))
                Image(uiImage:image).resizable().scaledToFit().frame(width:size.width,height:size.height)
                    .frame(maxWidth:.infinity,maxHeight:.infinity).padding(10).allowsHitTesting(false)
            } else { Text(result.outputLatex).font(.system(.body,design:.serif)).padding().frame(maxWidth:.infinity,maxHeight:.infinity) }
        }
        .frame(width:result.canvasWidth,height:result.canvasHeight)
        .foregroundStyle(FolioTheme.ink)
        .background(.white,in:RoundedRectangle(cornerRadius:10))
        .overlay(RoundedRectangle(cornerRadius:10).stroke(viewModel.selectedResultID == result.stableID ? Color.accentColor:Color.gray.opacity(0.5),lineWidth:1.5))
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance:2,coordinateSpace:.named("notebookPageViewport"))
            .onChanged { value in
                if start==nil { start=CGPoint(x:result.canvasX,y:result.canvasY);dragZoom=viewModel.viewport.zoom }
                viewModel.selectedResultID=result.stableID;viewModel.isDraggingResult=true
                translation=CGSize(width:value.translation.width/max(dragZoom,0.01),height:value.translation.height/max(dragZoom,0.01))
            }
            .onEnded { _ in
                defer { translation = .zero;start=nil;viewModel.isDraggingResult=false }
                let origin=start ?? CGPoint(x:result.canvasX,y:result.canvasY)
                do { try CanvasResultStore.move(result,to:CGPoint(x:origin.x+translation.width,y:origin.y+translation.height),context:context,history:viewModel.history,onError:report) }
                catch { report(error.localizedDescription) }
            })
        .scaleEffect(viewModel.viewport.zoom,anchor:.topLeading)
        .offset(x:(result.canvasX+translation.width)*viewModel.viewport.zoom-viewModel.viewport.offset.x,
                y:(result.canvasY+translation.height)*viewModel.viewport.zoom-viewModel.viewport.offset.y)
        .accessibilityElement(children:.contain).accessibilityIdentifier("insertedCanvasResult")
        .accessibilityLabel("Movable result: "+result.outputLatex)
        .task(id:result.stableID) {
            guard result.canvasPreviewVersion != CanvasResultLayout.previewVersion else { return }
            let id=result.stableID,latex=result.outputLatex
            do {
                let png=try await ResultImageRenderer.render(latex);try Task.checkCancellation()
                let descriptor=FetchDescriptor<ComputationResult>(predicate:#Predicate { $0.stableID == id })
                if let current=try context.fetch(descriptor).first,current.isPlacedOnCanvas,!current.isRemoved {
                    try CanvasResultStore.refreshPreview(current,preview:png,context:context)
                }
            } catch is CancellationError { }
            catch { report(error.localizedDescription) }
        }
        .onDisappear { if start != nil { viewModel.isDraggingResult=false } }
    }
    private func report(_ text:String) { viewModel.canvasError=text }
}
