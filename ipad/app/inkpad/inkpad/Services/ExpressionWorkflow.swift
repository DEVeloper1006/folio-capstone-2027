/* Tracks expression review state, schedules recognition and suggests operations while preserving worksheet notation semantics. */
import Foundation
import Observation
import CoreGraphics

/// Transcription state only: acceptance never means mathematical verification.
nonisolated enum ExpressionIndicatorState:String,Sendable {
    case collecting,reading,paused,review,accepted,stale,failed
    var title:String {
        switch self {
        case .collecting:"Ink changed";case .reading:"Reading…";case .paused:"Resume reading";case .review:"Review math"
        case .accepted:"Compute";case .stale:"Review changes";case .failed:"Retry reading"
        }
    }
    var symbol:String {
        switch self {
        case .collecting:"pencil";case .reading:"hourglass";case .paused:"pause.circle";case .review:"text.viewfinder"
        case .accepted:"function";case .stale:"arrow.triangle.2.circlepath";case .failed:"exclamationmark.bubble"
        }
    }
}

@MainActor
enum ExpressionWorkflow {
    static func state(_ step:Step,isRecognizing:Bool=true)->ExpressionIndicatorState {
        if step.isAccepted { return .accepted }
        switch step.recognitionState {
        case .collecting:return step.acceptedLatex.isEmpty ? .collecting:.stale
        case .recognizing:return isRecognizing ? .reading:.paused
        case .failed:return .failed
        case .ready,.ambiguous:return .review
        }
    }
}

/// Suggestions validate supported syntax only; no command runs until the user requests it.
nonisolated struct ExpressionComputeSuggestion:Equatable,Sendable {
    let operation:MathOperation
    let title:String
    static func forLatex(_ latex:String)->Self? {
        let text=latex.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty,text.count<=10_000 else { return nil }
        if text.contains("\\begin{") || text.contains(";") || text.contains("&") {
            guard (try? ExactMatrix.parse(text)) != nil else { return nil }
            return Self(operation:.rref,title:"RREF")
        }
        if text.contains("<") || text.contains(">") || text.contains("≤") || text.contains("≥") || text.contains("\\le") || text.contains("\\ge") {return Self(operation:.solveInequality,title:"Solve inequality")}
        if text.contains("="),(text.contains("|") || text.contains("\\vert") || text.contains("\\lvert") || text.hasPrefix("abs(")) {return Self(operation:.solveAbsolute,title:"Solve absolute value")}
        if text.range(of:#"(^|[^A-Za-z])i([^A-Za-z]|$)"#,options:.regularExpression) != nil,(try? ExactComplexValue.parse(text)) != nil {return Self(operation:.complexCalculate,title:"Calculate complex expression")}
        if text.contains("\\lim") { return Self(operation:.limit,title:"Find limit") }
        if let notation=try? WorksheetMathNotation.read(text) {
            if notation.kind == .partial { return Self(operation:.partialDerivative,title:"Find partial derivative") }
            if notation.kind == .derivative { return Self(operation:notation.order==2 ? .secondDerivative:.derivative,title:"Differentiate") }
            if notation.kind == .definition && !notation.arguments.isEmpty { return Self(operation:.derivative,title:"Differentiate") }
        }
        let algebra=AlgebraComputationService()
        if text.hasPrefix("y=") || text.hasPrefix("y =") || text.range(of:#"^[fgh]\s*\([A-Za-z]\)\s*="#,options:.regularExpression) != nil {
            return Self(operation:.derivative,title:"Differentiate")
        }
        if text.contains("=") {
            let parts=text.components(separatedBy:"=")
            guard parts.count==2,let a=try? algebra.prepared(parts[0]),let b=try? algebra.prepared(parts[1]),
                  Set([a.inferredVariable,b.inferredVariable].compactMap{$0}).count<=1,
                  let difference=try? a.integrand.adding(b.integrand.negated()),difference.degree<=2 else { return nil }
            return Self(operation:.solveEquation,title:"Solve equation")
        }
        if text.contains("\\int") || text.contains("∫") {
            guard let integral=try? PolynomialIntegralInput.parse(text) else {
                if text.contains("\\infty") || text.contains("∞") { return nil }
                // A hint only; the separate elementary parser validates on review.
                return Self(operation:text.contains("_") ? .definiteIntegral:.integral,title:text.contains("_") ? "Evaluate integral":"Integrate")
            }
            return integral.isDefinite ? Self(operation:.definiteIntegral,title:"Evaluate definite integral"):Self(operation:.integral,title:"Integrate")
        }
        guard let polynomial=try? algebra.prepared(text) else { return Self(operation:.derivative,title:"Differentiate") }
        return polynomial.inferredVariable==nil ? Self(operation:.arithmetic,title:"Calculate"):Self(operation:.simplify,title:"Simplify")
    }
}

/// A superseded task cannot clear the state of a newer scheduled recognition.
@MainActor @Observable
final class ExpressionRecognitionScheduler {
    private var task:Task<Void,Never>?
    private var revision=UUID()
    private(set) var isWaiting=false
    private(set) var isRunning=false
    func cancel() {
        revision=UUID();task?.cancel();task=nil;isWaiting=false;isRunning=false
    }
    func schedule(delay:Duration = .milliseconds(650),action:@escaping @MainActor () async->Void) {
        cancel();let request=revision;isWaiting=true
        task=Task { @MainActor in
            defer { if revision==request { isWaiting=false;isRunning=false;task=nil } }
            do { try await Task.sleep(for:delay);try Task.checkCancellation() } catch { return }
            guard revision==request else { return }
            isWaiting=false;isRunning=true
            await action()
        }
    }
}

nonisolated enum ExpressionIndicatorLayout {
    static let size=CGSize(width:132,height:36)
    static func frames(bounds:[CGRect],viewport:CanvasViewport,available:CGSize)->[CGRect] {
        var previousBottom:CGFloat = -.infinity
        return bounds.map { bounds in
            guard !bounds.isNull,bounds.minY.isFinite,bounds.maxX.isFinite else { return .null }
            let point=viewport.displayPoint(CGPoint(x:bounds.maxX+16,y:bounds.minY))
            let y=max(point.y,previousBottom+4)
            previousBottom=y+size.height
            // Keep controls at the trailing edge, away from the next symbol.
            return CGRect(x:max(8,available.width-size.width-8),y:y,width:size.width,height:size.height)
        }
    }
}

/// The exact transcription the user saw, independent of mutable Step objects.
nonisolated struct ExpressionPreviewSnapshot:Equatable,Sendable {
    let id:UUID
    let fingerprint:String
    let latex:String
    @MainActor init(_ step:Step) { id=step.stableID;fingerprint=step.strokeFingerprint;latex=step.ghostLaTeX }
    @MainActor func matches(_ step:Step)->Bool {
        id==step.stableID && fingerprint==step.strokeFingerprint && latex==step.ghostLaTeX
            && !step.isAccepted && [.ready,.ambiguous].contains(step.recognitionState)
    }
    var cacheKey:String { fingerprint+"|"+latex }
}

nonisolated enum ExpressionPreviewLayout {
    struct Placement { let frame:CGRect;let compact:Bool }
    static let cardSize=CGSize(width:220,height:158)
    static func expandedFrame(anchor:CGRect,available:CGSize)->CGRect {
        let top=min(64,max(8,available.height/5))
        let width=min(620,max(0,available.width-16)),height=min(480,max(0,available.height-top-8))
        return CGRect(x:max(8,available.width-width-8),y:max(top,min(anchor.minY,available.height-height-8)),width:width,height:height)
    }
    static func placements(bounds:[CGRect],pending:[Bool],obstacles:[CGRect],viewport:CanvasViewport,available:CGSize)->[Placement] {
        var bottom:CGFloat = 8
        return bounds.indices.map { i in
            let b=bounds[i]
            guard !b.isNull,b.minY.isFinite,b.maxY.isFinite,available.width>=148 else {return Placement(frame:.null,compact:true)}
            let top=viewport.displayPoint(b.origin).y,end=b.maxY*viewport.zoom-viewport.offset.y
            guard end>=0,top<available.height else {return Placement(frame:.null,compact:true)}
            let width=min(cardSize.width,available.width-16)
            let full=pending[i] && available.height>=cardSize.height+16
            let height=full ? cardSize.height:ExpressionIndicatorLayout.size.height
            let y=max(8,max(top,bottom))
            let frame=CGRect(x:available.width-width-8,y:y,width:width,height:height)
            bottom=frame.maxY+8
            // The rail follows visible rows. Tall/dense groups remain reachable
            // by scrolling the notebook; expanded math has its own scroll view.
            return Placement(frame:frame,compact:!full)
        }
    }
}

#if DEBUG
struct InlineRecognitionFixture:RecognitionService {
    let identifier="inline-fixture"
    func recognize(inkData:Data,mode:MathMode) async throws->RecognitionResult {
        try await Task.sleep(for:.milliseconds(150))
        let latex=ProcessInfo.processInfo.arguments.contains("--wide-inline-preview-ui") ? (1...50).map{"x_{\($0)}"}.joined(separator:"+"):"x^2+3=12"
        return RecognitionResult(text:latex,latex:latex,confidence:nil)
    }
}
#endif
