import SwiftUI

/// Previews stay in the trailing row-control rail. Expanded math scrolls
/// independently without moving notebook strokes or result cards. All other touches still reach PencilKit through the hit-test gate.
struct ExpressionIndicatorLayer:View {
    let steps:[Step]
    let viewport:CanvasViewport
    let available:CGSize
    let isRecognizing:Bool
    var obstacles:[CGRect]=[]
    let onAccept:(ExpressionPreviewSnapshot)->Void
    let onOpen:(UUID)->Void
    @State private var expanded:UUID?
    var body:some View {
        let pending=steps.map{ExpressionWorkflow.state($0,isRecognizing:isRecognizing) == .review && !$0.ghostLaTeX.isEmpty}
        let placements=ExpressionPreviewLayout.placements(bounds:steps.map(\.bounds),pending:pending,obstacles:obstacles,viewport:viewport,available:available)
        let items=steps.enumerated().compactMap { i,step -> ExpressionPreviewItem? in
            let placement=placements[i]
            guard !placement.frame.isNull else {return nil}
            let isExpanded=expanded==step.stableID && pending[i]
            var frame=placement.frame
            if isExpanded {
                frame=ExpressionPreviewLayout.expandedFrame(anchor:frame,available:available)
            }
            return ExpressionPreviewItem(id:step.stableID,row:step.sortIndex+1,state:ExpressionWorkflow.state(step,isRecognizing:isRecognizing),
                snapshot:ExpressionPreviewSnapshot(step),frame:frame,railFrame:placement.frame,showPreview:pending[i] && (!placement.compact || isExpanded),expanded:isExpanded)
        }
        ExpressionPreviewHost(items:items,onAccept:{ snapshot in expanded=nil;onAccept(snapshot) },onOpen:{ id in expanded=nil;onOpen(id) },onExpand:{ expanded=$0 })
            .onChange(of:steps.map{ExpressionPreviewSnapshot($0)}) { _,_ in expanded=nil }
    }
}

private struct ExpressionPreviewItem:Identifiable {
    let id:UUID
    let row:Int
    let state:ExpressionIndicatorState
    let snapshot:ExpressionPreviewSnapshot
    let frame:CGRect
    let railFrame:CGRect
    let showPreview:Bool
    let expanded:Bool
}

private struct ExpressionPreviewHost:UIViewRepresentable {
    let items:[ExpressionPreviewItem]
    let onAccept:(ExpressionPreviewSnapshot)->Void
    let onOpen:(UUID)->Void
    let onExpand:(UUID?)->Void
    private func content(_ view:ResultHitTestView)->ExpressionIndicatorContent {
        .init(items:items,onAccept:onAccept,onOpen:onOpen,onExpand:onExpand,onFrames:{ [weak view] in view?.interactiveRects=$0 })
    }
    func makeCoordinator()->Coordinator {Coordinator()}
    func makeUIView(context:Context)->ResultHitTestView {
        let view=ResultHitTestView();view.backgroundColor = .clear
        let host=UIHostingController(rootView:content(view));context.coordinator.host=host
        host.view.backgroundColor = .clear;host.view.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(host.view)
        NSLayoutConstraint.activate([host.view.leadingAnchor.constraint(equalTo:view.leadingAnchor),host.view.trailingAnchor.constraint(equalTo:view.trailingAnchor),host.view.topAnchor.constraint(equalTo:view.topAnchor),host.view.bottomAnchor.constraint(equalTo:view.bottomAnchor)])
        return view
    }
    func updateUIView(_ view:ResultHitTestView,context:Context) {
        context.coordinator.host?.rootView=content(view)
    }
    final class Coordinator {var host:UIHostingController<ExpressionIndicatorContent>?}
}

private struct PreviewFramePreference:PreferenceKey {
    static let defaultValue:[CGRect]=[]
    static func reduce(value:inout [CGRect],nextValue:()->[CGRect]) {value += nextValue()}
}
private struct ExpressionIndicatorContent:View {
    let items:[ExpressionPreviewItem]
    let onAccept:(ExpressionPreviewSnapshot)->Void
    let onOpen:(UUID)->Void
    let onExpand:(UUID?)->Void
    let onFrames:([CGRect])->Void
    var body:some View {
        ZStack(alignment:.topLeading) {
            ScrollView(.vertical) {
                LazyVStack(alignment:.leading,spacing:0) {
                    ForEach(Array(items.enumerated()),id:\.element.id) {index,item in
                        Group {
                            if item.expanded {Color.clear.frame(width:item.railFrame.width,height:item.railFrame.height)}
                            else {row(item)}
                        }.padding(.top,max(0,item.railFrame.minY-(index==0 ? 0:items[index-1].railFrame.maxY)))
                    }
                }.frame(maxWidth:.infinity,alignment:.topLeading)
            }.accessibilityIdentifier("recognitionSideRail")
            ForEach(items.filter(\.expanded)) {item in row(item).zIndex(1)}
        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
            .coordinateSpace(name:"recognitionPreviewViewport").clipped()
            .onPreferenceChange(PreviewFramePreference.self,perform:onFrames)
    }
    private func row(_ item:ExpressionPreviewItem)->some View {
        Group {
            if item.showPreview {
                InlineMathPreview(item:item,onAccept:onAccept,onOpen:onOpen,onClose:{onExpand(nil)},onExpandPreview:{onExpand(item.id)})
            } else {
                Button {onOpen(item.id)} label: {
                    HStack(spacing:6) {
                        if item.state == .reading {ProgressView().controlSize(.mini)}
                        else {Image(systemName:item.state.symbol)}
                        Text(item.state.title).font(.system(size:12,weight:.medium)).lineLimit(1)
                    }.frame(width:item.frame.width,height:item.frame.height)
                        .background(.regularMaterial,in:Capsule())
                }.buttonStyle(.plain)
                    .accessibilityIdentifier("expressionIndicator-"+item.id.uuidString)
                    .accessibilityLabel("Row \(item.row), \(item.state.title)").accessibilityValue(item.state.rawValue)
            }
        }.frame(width:item.frame.width,height:item.frame.height)
            .background(GeometryReader { geo in Color.clear.preference(key:PreviewFramePreference.self,value:[geo.frame(in:.named("recognitionPreviewViewport"))]) })
            .offset(x:item.frame.minX,y:item.expanded ? item.frame.minY:0)
    }
}

/// Serialized offscreen rendering with bounded memory, shared by visible rows.
@MainActor
private final class InlineMathPreviewRenderer {
    static let shared=InlineMathPreviewRenderer()
    private let cache=NSCache<NSString,UIImage>()
    private var rendering=false
    init() {cache.countLimit=40;cache.totalCostLimit=16*1024*1024}
    func image(_ snapshot:ExpressionPreviewSnapshot) async throws -> UIImage {
        let key=snapshot.cacheKey as NSString
        if let image=cache.object(forKey:key) {return image}
        while rendering {try await Task.sleep(for:.milliseconds(40))}
        try Task.checkCancellation()
        if let image=cache.object(forKey:key) {return image}
        rendering=true;defer {rendering=false}
        let result=try await ResultImageRenderer.snapshot(snapshot.latex,forRecognition:true)
        try Task.checkCancellation()
        guard let dataImage=UIImage(data:result.png),let cgImage=dataImage.cgImage else {throw PolynomialError.invalid("Preview could not be decoded.")}
        let image=UIImage(cgImage:cgImage,scale:result.scale,orientation:.up)
        cache.setObject(image,forKey:key,cost:(image.cgImage?.bytesPerRow ?? 0)*(image.cgImage?.height ?? 0))
        return image
    }
}

private struct InlineMathPreview:View {
    let item:ExpressionPreviewItem
    let onAccept:(ExpressionPreviewSnapshot)->Void
    let onOpen:(UUID)->Void
    let onClose:()->Void
    let onExpandPreview:()->Void
    @State private var rendered:(key:String,image:UIImage)?
    @State private var failed=false
    var body:some View {
        let current=rendered?.key==item.snapshot.cacheKey ? rendered?.image:nil
        VStack(spacing:6) {
            HStack(spacing:6) {
                Button {onOpen(item.id)} label: {Label("Review math",systemImage:"function").font(.caption.weight(.medium))}
                    .accessibilityIdentifier("expressionIndicator-"+item.id.uuidString).accessibilityValue(item.state.rawValue)
                Spacer(minLength:0)
                Button {if item.expanded {onClose()} else {onExpandPreview()}} label: {
                    Image(systemName:item.expanded ? "arrow.down.right.and.arrow.up.left":"arrow.up.left.and.arrow.down.right")
                }.accessibilityLabel(item.expanded ? "Shrink preview":"Expand preview")
                    .accessibilityIdentifier("expandMathPreview-"+item.id.uuidString)
            }.frame(height:30)
            if let current {
                if item.expanded {
                    ScrollView([.horizontal,.vertical]) {
                        Image(uiImage:current).resizable().frame(width:current.size.width*1.5,height:current.size.height*1.5).padding(8)
                    }.accessibilityIdentifier("expandedMathScroll")
                } else {
                    Image(uiImage:current).resizable().scaledToFit()
                        .frame(width:min(current.size.width*1.25,item.frame.width-16),height:min(current.size.height*1.25,64))
                        .frame(maxWidth:.infinity,maxHeight:.infinity)
                        .accessibilityLabel("Recognized math: "+item.snapshot.latex)
                }
            } else if failed {
                Text("Preview unavailable. Tap Review math to correct it.").font(.caption).frame(maxHeight:.infinity)
            } else {ProgressView("Preparing preview…").font(.caption).frame(maxHeight:.infinity)}
            Button {onAccept(item.snapshot)} label:{Label("Accept",systemImage:"checkmark").frame(maxWidth:.infinity)}
                .buttonStyle(.borderedProminent).controlSize(.small).disabled(current==nil)
                .accessibilityIdentifier("inlineAcceptExpression-"+item.id.uuidString)
        }.padding(8).frame(maxWidth:.infinity,maxHeight:.infinity)
            .foregroundStyle(Color.primary).background(.regularMaterial,in:RoundedRectangle(cornerRadius:10))
            .overlay(RoundedRectangle(cornerRadius:10).stroke(Color.secondary.opacity(0.35),lineWidth:0.5))
            .accessibilityElement(children:.contain).accessibilityIdentifier("inlineMathPreview-"+item.id.uuidString)
            .onDisappear {rendered=nil}
            .task(id:item.snapshot.cacheKey) {
                rendered=nil;failed=false
                do {let image=try await InlineMathPreviewRenderer.shared.image(item.snapshot);try Task.checkCancellation();rendered=(item.snapshot.cacheKey,image)}
                catch is CancellationError {} catch {failed=true}
            }
    }
}

struct InlineExpressionTarget:Identifiable { let id:UUID }

struct InlineExpressionInspector:View {
    @Environment(\.dismiss) private var dismiss
    let step:Step
    let alternatives:[String]
    let busy:Bool
    let onAccept:(Step,String)->Void
    let onRetry:()->Void
    let onInsert:@MainActor @Sendable (UUID) async throws->Void
    let onRemove:(ComputationResult)throws->Void
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:12) {
                    Text("Check the preview, then choose a calculation.").font(.callout).foregroundStyle(.secondary)
                    ExpressionReviewRow(step:step,alternatives:alternatives,duration:step.recognitionMilliseconds,busy:busy,onAccept:onAccept,onInsert:{ id in try await onInsert(id) },onRemove:onRemove)
                    Button(busy ? "Reading handwriting…":"Recognize changed ink / retry",action:onRetry)
                        .disabled(busy).accessibilityIdentifier("inlineRetryRecognition")
                }.padding()
            }.scrollDismissesKeyboard(.interactively).accessibilityIdentifier("inlineInspectorScroll")
            .navigationTitle("Row \(step.sortIndex+1)")
            .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("closeExpressionInspector") } }
        }.presentationDetents([.height(580),.large]).presentationDragIndicator(.visible)
    }
}
