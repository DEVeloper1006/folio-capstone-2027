import Foundation
import WebKit
import UIKit
import CoreGraphics

@MainActor
enum ResultImageRenderer {
    struct Snapshot {
        let png:Data
        let logicalSize:CGSize
        let scale:CGFloat
    }
    static func render(_ latex:String) async throws -> Data { try await snapshot(latex).png }
    static func snapshot(_ latex:String,forRecognition:Bool=false) async throws -> Snapshot {
        let renderScale:CGFloat=forRecognition ? 2:CanvasResultLayout.previewScale
        guard let asset=Bundle.main.url(forResource:"tex-svg",withExtension:"js") else { throw PolynomialError.invalid("The bundled math renderer is unavailable.") }
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent("CanvasMathImages",isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let script=directory.appendingPathComponent("tex-svg.js")
        if !FileManager.default.fileExists(atPath:script.path) { try FileManager.default.copyItem(at:asset,to:script) }
        let file=directory.appendingPathComponent("render-"+UUID().uuidString+".html")
        try MathJaxWebView.html.write(to:file,atomically:true,encoding:.utf8)
        defer { try? FileManager.default.removeItem(at:file) }
        let browser=WKWebView(frame:CGRect(x:0,y:0,width:1200,height:400))
        browser.overrideUserInterfaceStyle = .light
        guard let scene=UIApplication.shared.connectedScenes.compactMap({$0 as? UIWindowScene}).first else { throw PolynomialError.invalid("Open the notebook before inserting a result.") }
        let window=UIWindow(windowScene:scene)
        window.windowLevel=UIWindow.Level(rawValue:UIWindow.Level.normal.rawValue-1)
        window.frame=browser.frame;window.rootViewController=UIViewController()
        window.rootViewController!.view.addSubview(browser);window.isHidden=false
        defer { browser.stopLoading();window.isHidden=true;browser.removeFromSuperview() }
        browser.loadFileURL(file,allowingReadAccessTo:directory)
        for _ in 0..<100 {
            try Task.checkCancellation()
            if let ready=try? await browser.evaluateJavaScript("typeof window.renderRows==='function' && !!window.MathJax && !!MathJax.startup"),ready as? Bool == true {
                _=try await browser.callAsyncJavaScript("await window.renderRows(rows);",arguments:["rows":[latex]],in:nil,contentWorld:.page)
                let hasError=try await browser.evaluateJavaScript(#"!!document.querySelector('[data-mml-node="merror"]')"#)
                guard hasError as? Bool != true else { throw PolynomialError.invalid("The expression could not be typeset. Review math and correct its notation.") }
                guard let box=try await browser.evaluateJavaScript("(()=>{let e=document.querySelector('mjx-container svg');if(!e)return null;let r=e.getBoundingClientRect();return {x:r.x,y:r.y,width:r.width,height:r.height}})()") as? [String:Double],
                      let x=box["x"],let y=box["y"],let width=box["width"],let height=box["height"],width>0,height>0,width<(forRecognition ? 6000:2600),height<(forRecognition ? 1400:380),width*height<(forRecognition ? 400_000:988_000) else {
                    throw PolynomialError.invalid("This expression is too large to place on the page. It remains available in the preview.")
                }
                browser.frame.size=CGSize(width:max(1200,x+width+12),height:max(400,y+height+12))
                let config=WKPDFConfiguration()
                config.rect=CGRect(x:max(0,x-6),y:max(0,y-6),width:width+12,height:height+12)
                let pdf=try await browser.pdf(configuration:config)
                guard let provider=CGDataProvider(data:pdf as CFData),let document=CGPDFDocument(provider),let page=document.page(at:1) else {
                    throw PolynomialError.invalid("Could not render the math PDF.")
                }
                let logical=page.getBoxRect(.mediaBox).size
                let pixels=CGSize(width:ceil(logical.width*renderScale),height:ceil(logical.height*renderScale))
                // PDFKit thumbnails use display-dependent UIImage scales. Rasterize
                // explicitly at scale=1 so PNG pixels always mean exactly 3× points.
                let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=true
                let image=UIGraphicsImageRenderer(size:pixels,format:format).image { context in
                    UIColor.white.setFill();context.fill(CGRect(origin:.zero,size:pixels))
                    let cg=context.cgContext
                    cg.translateBy(x:0,y:pixels.height);cg.scaleBy(x:1,y:-1)
                    cg.concatenate(page.getDrawingTransform(.mediaBox,rect:CGRect(origin:.zero,size:pixels),rotate:0,preserveAspectRatio:true))
                    cg.drawPDFPage(page)
                }
                guard let full=image.cgImage else { throw PolynomialError.invalid("Could not read rendered math pixels.") }
                let gray=try ImagePreprocessor.grayscale(full)
                var left=full.width,top=full.height,right = -1,bottom = -1
                for row in 0..<full.height {
                    for col in 0..<full.width where gray[row*full.width+col]<235 {
                        left=min(left,col);right=max(right,col);top=min(top,row);bottom=max(bottom,row)
                    }
                }
                guard right>=left,bottom>=top else { throw PolynomialError.invalid("The rendered result is blank.") }
                // WebKit PDF output can scale CSS content within its media box.
                // Restore the measured SVG's CSS point size after finding ink;
                // PDF page bounds alone are not the visible expression bounds.
                let inkWidth=CGFloat(right-left+1),inkHeight=CGFloat(bottom-top+1)
                let pointsPerPixel=min(width/inkWidth,height/inkHeight)
                let content=CGSize(width:inkWidth*pointsPerPixel,height:inkHeight*pointsPerPixel)
                let logicalSize=CGSize(width:ceil(content.width+12),height:ceil(content.height+12))
                guard let ink=full.cropping(to:CGRect(x:CGFloat(left),y:CGFloat(top),width:inkWidth,height:inkHeight)) else {
                    throw PolynomialError.invalid("Could not crop the result image.")
                }
                let target=CGSize(width:logicalSize.width*renderScale,height:logicalSize.height*renderScale)
                let normalized=UIGraphicsImageRenderer(size:target,format:format).image { context in
                    UIColor.white.setFill();context.fill(CGRect(origin:.zero,size:target))
                    UIImage(cgImage:ink).draw(in:CGRect(x:6*renderScale,y:6*renderScale,width:content.width*renderScale,height:content.height*renderScale))
                }
                guard let data=normalized.pngData() else { throw PolynomialError.invalid("Could not encode the result image.") }
                return Snapshot(png:data,logicalSize:logicalSize,scale:renderScale)
            }
            try await Task.sleep(for:.milliseconds(100))
        }
        throw PolynomialError.invalid("The math preview did not load. Try inserting again.")
    }
}
