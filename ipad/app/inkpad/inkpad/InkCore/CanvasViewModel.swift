/* Owns PencilKit drawing state, tool contact, history and persistence callbacks. */
import SwiftUI
import PencilKit

nonisolated enum DrawingTool:String,CaseIterable,Identifiable {
    case pen,highlighter,eraser,lasso
    var id:String { rawValue }
    var label:String { switch self { case .pen:"Pen";case .highlighter:"Highlighter";case .eraser:"Eraser";case .lasso:"Lasso" } }
    var icon:String { switch self { case .pen:"pencil.tip";case .highlighter:"highlighter";case .eraser:"eraser";case .lasso:"lasso" } }
    var widthRange:ClosedRange<CGFloat> {
        switch self {
        case .pen:PKInkingTool.InkType.pen.validWidthRange
        case .highlighter:PKInkingTool.InkType.marker.validWidthRange
        case .eraser:PKEraserTool.EraserType.fixedWidthBitmap.validWidthRange
        case .lasso:1...1
        }
    }
}

nonisolated enum InkColor:String,CaseIterable,Identifiable {
    case black,blue,red
    var id:String { rawValue }
    var uiColor:UIColor { switch self { case .black:.black;case .blue:UIColor(red:0.2,green:0.4,blue:0.72,alpha:1);case .red:UIColor(red:0.75,green:0.25,blue:0.22,alpha:1) } }
    var color:Color { Color(uiColor:uiColor) }
}

nonisolated struct CanvasViewport:Equatable,Sendable {
    var offset:CGPoint = .zero
    var zoom:CGFloat = 1
    func displayPoint(_ point:CGPoint)->CGPoint { CGPoint(x:point.x*zoom-offset.x,y:point.y*zoom-offset.y) }
    func pageTranslation(_ translation:CGSize)->CGSize { CGSize(width:translation.width/max(zoom,0.01),height:translation.height/max(zoom,0.01)) }
}

@MainActor @Observable
final class CanvasViewModel {
    nonisolated deinit {}
    var drawing:PKDrawing
    var backgroundStyle:PageBackgroundStyle
    var allowFingerDrawing=true { didSet { preferences.set(allowFingerDrawing,forKey:"canvas.allowFingerDrawing") } }
    var settingsTool:DrawingTool?
    var currentTool:DrawingTool = .pen
    private(set) var previousTool:DrawingTool = .pen
    private(set) var lastInkingTool:DrawingTool = .pen
    var inkColor:Color = .black { didSet { saveToolPreferences() } }
    var penWidth:CGFloat = 2 { didSet { saveToolPreferences() } }
    var highlighterWidth:CGFloat = 15 { didSet { saveToolPreferences() } }
    var eraserWidth:CGFloat = 20 { didSet { saveToolPreferences() } }
    var sessionMode:SessionMode = .coach
    var mathMode:MathMode = .linalg
    var showTypeset=true
    var selectedStrokesBounds:CGRect?
    var showRadialMenu=false
    var viewport=CanvasViewport()
    var pageHeight:CGFloat=2048
    var selectedResultID:UUID?
    var isDraggingResult=false
    var focusID=UUID()
    var focusRect:CGRect?
    private(set) var canUndo=false
    private(set) var canRedo=false
    @ObservationIgnored let history=UndoManager()
    @ObservationIgnored weak var canvas:PKCanvasView?
    @ObservationIgnored private var undoObserver:NSObjectProtocol?
    @ObservationIgnored private var loadingPreferences=true
    @ObservationIgnored private let preferences:UserDefaults
    @ObservationIgnored private var autosaveTask:Task<Void,Never>?
    private(set) var isUsingTool=false
    var onToolActivityChanged:((Bool)->Void)?
    var onDrawingChanged:((Data)->Void)?
    var onSave:((Data,PageBackgroundStyle)->Void)?
    var canvasError=""

    init(drawingData:Data?=nil,backgroundStyle:PageBackgroundStyle = .dot,mathMode:MathMode = .linalg,preferences:UserDefaults = .standard) {
        self.preferences=preferences
        drawing=drawingData.flatMap { try? PKDrawing(data:$0) } ?? PKDrawing()
        self.backgroundStyle=backgroundStyle;self.mathMode=mathMode
        if let rgba=preferences.array(forKey:"canvas.inkRGBA") as? [Double],rgba.count==4 {
            inkColor=Color(.sRGB,red:rgba[0],green:rgba[1],blue:rgba[2],opacity:rgba[3])
        }
        if preferences.object(forKey:"canvas.penWidth") != nil { penWidth=Self.clamp(CGFloat(preferences.double(forKey:"canvas.penWidth")),to:.pen) }
        if preferences.object(forKey:"canvas.markerWidth") != nil { highlighterWidth=Self.clamp(CGFloat(preferences.double(forKey:"canvas.markerWidth")),to:.highlighter) }
        if preferences.object(forKey:"canvas.eraserWidth") != nil { eraserWidth=Self.clamp(CGFloat(preferences.double(forKey:"canvas.eraserWidth")),to:.eraser) }
        if preferences.object(forKey:"canvas.allowFingerDrawing") != nil { allowFingerDrawing=preferences.bool(forKey:"canvas.allowFingerDrawing") }
        history.levelsOfUndo=100;loadingPreferences=false
    }
    /// PKDrawing.bounds is CGRect.null for empty/fully erased ink. Never feed
    /// its infinite maxY into UIScrollView contentSize or page export sizes.
    static func contentHeight(drawing:PKDrawing,resultBottom:CGFloat=0)->CGFloat {
        let bounds=drawing.bounds
        let inkBottom = !bounds.isNull && !bounds.isEmpty && bounds.maxY.isFinite ? max(0,bounds.maxY)+80:0
        let resultBottom = resultBottom.isFinite ? max(0,resultBottom):0
        return max(2048,inkBottom,resultBottom)
    }
    var uiInkColor:UIColor { UIColor(inkColor).resolvedColor(with:UITraitCollection(userInterfaceStyle:.light)) }
    func matchesInk(_ color: UIColor) -> Bool {
        func components(_ value: UIColor) -> [CGFloat] {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            value.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return [red, green, blue, alpha]
        }
        return zip(components(uiInkColor), components(color)).allSatisfy { abs($0.0 - $0.1) < 0.001 }
    }
    var pkTool:PKTool {
        switch currentTool {
        case .pen:PKInkingTool(.pen,color:uiInkColor,width:penWidth)
        case .highlighter:PKInkingTool(.marker,color:uiInkColor.withAlphaComponent(0.3),width:highlighterWidth)
        case .eraser:PKEraserTool(.fixedWidthBitmap,width:eraserWidth)
        case .lasso:PKLassoTool()
        }
    }
    func width(for tool:DrawingTool)->CGFloat {
        switch tool { case .pen:penWidth;case .highlighter:highlighterWidth;case .eraser:eraserWidth;case .lasso:1 }
    }
    func setWidth(_ width:CGFloat,for tool:DrawingTool) {
        let value=Self.clamp(width,to:tool)
        switch tool { case .pen:penWidth=value;case .highlighter:highlighterWidth=value;case .eraser:eraserWidth=value;case .lasso:break }
    }
    private static func clamp(_ value:CGFloat,to tool:DrawingTool)->CGFloat {
        guard value.isFinite else { return tool.widthRange.lowerBound }
        return min(max(value,tool.widthRange.lowerBound),tool.widthRange.upperBound)
    }
    func tapToolbarTool(_ tool:DrawingTool) {
        if currentTool == tool { settingsTool = settingsTool == tool ? nil:tool }
        else { toggleTool(to:tool);settingsTool=nil }
    }
    func toggleTool(to tool:DrawingTool) {
        if currentTool != tool { previousTool=currentTool }
        currentTool=tool
        if tool == .pen || tool == .highlighter { lastInkingTool=tool }
        selectedResultID=nil
        isDraggingResult=false
        if tool != .lasso { selectedStrokesBounds=nil;showRadialMenu=false }
    }
    func handlePencilDoubleTap(_ action:UIPencilPreferredAction) {
        switch action {
        case .switchEraser: toggleTool(to:currentTool == .eraser ? lastInkingTool:.eraser)
        case .switchPrevious: toggleTool(to:previousTool)
        default: return
        }
        settingsTool=nil
    }
    func attach(_ canvas:PKCanvasView) {
        self.canvas=canvas
        if let undoObserver { NotificationCenter.default.removeObserver(undoObserver) }
        undoObserver=NotificationCenter.default.addObserver(forName:nil,object:history,queue:.main) { [weak self] _ in
            guard let target=self else { return }
            Task { @MainActor in target.refreshUndoState() }
        }
        refreshUndoState()
    }
    func detach() {
        if let undoObserver { NotificationCenter.default.removeObserver(undoObserver) }
        toolActivityChanged(false)
        undoObserver=nil;history.removeAllActions();canvas=nil;refreshUndoState()
    }
    func refreshUndoState() { canUndo=history.canUndo;canRedo=history.canRedo }
    func undo() { guard history.canUndo else { return };history.undo();refreshUndoState() }
    func redo() { guard history.canRedo else { return };history.redo();refreshUndoState() }
    /// Publish contact changes so automatic recognition can wait until a stroke finishes.
    func toolActivityChanged(_ active:Bool) {
        guard isUsingTool != active else { return }
        isUsingTool=active;onToolActivityChanged?(active)
    }
    func drawingChanged(_ value:PKDrawing) {
        drawing=value;onDrawingChanged?(value.dataRepresentation());scheduleAutosave()
        Task { @MainActor [weak self] in self?.refreshUndoState() }
    }
    func requestFocus(_ rect:CGRect) { focusRect=rect;focusID=UUID() }
    func save() { autosaveTask?.cancel();onSave?(drawing.dataRepresentation(),backgroundStyle) }
    func cycleMathMode() { mathMode=mathMode.next }
    private func scheduleAutosave() {
        autosaveTask?.cancel();autosaveTask=Task { @MainActor in
            try? await Task.sleep(for:.seconds(1));guard !Task.isCancelled else { return };save()
        }
    }
    private func saveToolPreferences() {
        guard !loadingPreferences else { return }
        var red:CGFloat=0,green:CGFloat=0,blue:CGFloat=0,alpha:CGFloat=1
        uiInkColor.getRed(&red,green:&green,blue:&blue,alpha:&alpha)
        preferences.set([Double(red),Double(green),Double(blue),Double(alpha)],forKey:"canvas.inkRGBA")
        preferences.set(Double(penWidth),forKey:"canvas.penWidth")
        preferences.set(Double(highlighterWidth),forKey:"canvas.markerWidth")
        preferences.set(Double(eraserWidth),forKey:"canvas.eraserWidth")
    }
}
