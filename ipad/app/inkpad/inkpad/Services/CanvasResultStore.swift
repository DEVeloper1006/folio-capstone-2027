import Foundation
import SwiftData
import CoreGraphics
import UIKit

/// Cached result PNGs are rendered at 3 pixels per logical point. Keep text
/// at its natural point size; only shrink oversized expressions to fit.
nonisolated enum CanvasResultLayout {
    static let previewScale:CGFloat=3
    static let previewVersion=4
    static func displaySize(pixels:CGSize,available:CGSize)->CGSize {
        guard pixels.width.isFinite,pixels.height.isFinite,pixels.width>0,pixels.height>0,
              available.width.isFinite,available.height.isFinite,available.width>0,available.height>0 else { return .zero }
        let natural=CGSize(width:pixels.width/previewScale,height:pixels.height/previewScale)
        let scale=min(1,available.width/natural.width,available.height/natural.height)
        return CGSize(width:natural.width*scale,height:natural.height*scale)
    }
    static func cardSize(pixels:CGSize)->CGSize {
        let content=displaySize(pixels:pixels,available:CGSize(width:576,height:380))
        return CGSize(width:max(180,ceil(content.width)+24),height:max(96,ceil(content.height)+60))
    }
}

nonisolated struct CanvasResultState:Equatable,Sendable {
    var inserted:Bool
    var removed:Bool
    var x:Double
    var y:Double
    var width:Double
    var height:Double
}

@MainActor
enum CanvasResultStore {
    static func state(_ result:ComputationResult)->CanvasResultState {
        CanvasResultState(inserted:result.isPlacedOnCanvas,removed:result.isRemoved,x:result.canvasX,y:result.canvasY,width:result.canvasWidth,height:result.canvasHeight)
    }
    static func insert(_ result:ComputationResult,preview:Data,context:ModelContext,history:UndoManager?,onError:@escaping @MainActor(String)->Void) throws {
        guard result.isCurrent,let page=result.source?.page else { throw PolynomialError.invalid("Review the current source and recompute before inserting this result.") }
        if result.isPlacedOnCanvas { return }
        var next=state(result);next.inserted=true
        guard let image=UIImage(data:preview)?.cgImage else { throw PolynomialError.invalid("The result image could not be read.") }
        let size=CanvasResultLayout.cardSize(pixels:CGSize(width:image.width,height:image.height))
        next.width=Double(size.width);next.height=Double(size.height)
        let source=result.source!.bounds
        var rect=CGRect(x:min(max(16,source.minX),1024-CGFloat(next.width)),y:max(16,source.maxY+24),width:next.width,height:next.height)
        let obstacles=page.steps.filter(\.isActive).map(\.bounds)+page.steps.flatMap(\.computationResults)
            .filter { $0 !== result && $0.isPlacedOnCanvas && !$0.isRemoved }.map(\.canvasRect)
        for _ in 0...obstacles.count {
            let collisions=obstacles.filter { $0.insetBy(dx:-8,dy:-8).intersects(rect) }
            guard let bottom=collisions.map(\.maxY).max() else { break }
            rect.origin.y=bottom+16
        }
        next.x=rect.minX;next.y=rect.minY
        let previousPreview=result.canvasPreviewPNG,previousVersion=result.canvasPreviewVersion;result.canvasPreviewPNG=preview;result.canvasPreviewVersion=CanvasResultLayout.previewVersion
        do { try apply(next,to:result,context:context,history:history,name:"Insert result",onError:onError) }
        catch { result.canvasPreviewPNG=previousPreview;result.canvasPreviewVersion=previousVersion;throw error }
    }
    static func refreshPreview(_ result:ComputationResult,preview:Data,context:ModelContext) throws {
        guard result.isPlacedOnCanvas,!result.isRemoved,let image=UIImage(data:preview)?.cgImage else {
            throw PolynomialError.invalid("The result is no longer on this page.")
        }
        let previous=(result.canvasPreviewPNG,result.canvasPreviewVersion,result.canvasWidth,result.canvasHeight,result.canvasX)
        let size=CanvasResultLayout.cardSize(pixels:CGSize(width:image.width,height:image.height))
        result.canvasPreviewPNG=preview;result.canvasPreviewVersion=CanvasResultLayout.previewVersion
        result.canvasWidth=size.width;result.canvasHeight=size.height;result.canvasX=min(max(0,result.canvasX),1024-size.width)
        do { try context.save() }
        catch {
            result.canvasPreviewPNG=previous.0;result.canvasPreviewVersion=previous.1
            result.canvasWidth=previous.2;result.canvasHeight=previous.3;result.canvasX=previous.4;throw error
        }
    }
    static func move(_ result:ComputationResult,to point:CGPoint,context:ModelContext,history:UndoManager?,onError:@escaping @MainActor(String)->Void) throws {
        guard point.x.isFinite,point.y.isFinite else { throw PolynomialError.invalid("Invalid result position.") }
        var next=state(result)
        next.x=Double(min(max(0,point.x),max(0,1024-CGFloat(next.width))))
        next.y=Double(min(max(0,point.y),100_000))
        try apply(next,to:result,context:context,history:history,name:"Move result",onError:onError)
    }
    static func removeFromCanvas(_ result:ComputationResult,context:ModelContext,history:UndoManager?,onError:@escaping @MainActor(String)->Void) throws {
        var next=state(result);next.inserted=false
        try apply(next,to:result,context:context,history:history,name:"Remove from page",onError:onError)
    }
    static func removeResult(_ result:ComputationResult,context:ModelContext,history:UndoManager?,onError:@escaping @MainActor(String)->Void) throws {
        var next=state(result);next.removed=true;next.inserted=false
        try apply(next,to:result,context:context,history:history,name:"Remove result",onError:onError)
    }
    private static func assign(_ value:CanvasResultState,to result:ComputationResult) {
        result.isPlacedOnCanvas=value.inserted;result.isRemoved=value.removed
        result.canvasX=value.x;result.canvasY=value.y;result.canvasWidth=value.width;result.canvasHeight=value.height
    }
    private static func apply(_ value:CanvasResultState,to result:ComputationResult,context:ModelContext,history:UndoManager?,name:String,onError:@escaping @MainActor(String)->Void) throws {
        let previous=state(result)
        guard previous != value else { return }
        assign(value,to:result)
        do { try context.save() } catch { assign(previous,to:result);throw error }
        history?.registerUndo(withTarget:result) { [weak history] target in
            MainActor.assumeIsolated {
                do { try apply(previous,to:target,context:context,history:history,name:name,onError:onError) }
                catch { onError(error.localizedDescription) }
            }
        }
        history?.setActionName(name)
    }
}
