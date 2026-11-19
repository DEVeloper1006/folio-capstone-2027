/* Runs bounded calculus inspection and execution in isolated, time-limited workers with versioned integration verification. */
import Foundation
import WebKit
import UIKit

nonisolated struct Calc1InputReview:Codable,Equatable,Sendable {
    let variable:String
    let integrand:String
    let kind:String
    let lower:String?
    let upper:String?
    let point:String?
    let direction:String?
}

@MainActor
enum Calc1MathService {
    static let version="native-math-calc1-v2-nerdamer-2.0.1"
    static func supports(_ operation:MathOperation)->Bool { !operation.isMatrix && !operation.isNativeAlgebraExtension && ![.factor,.solveEquation,.polynomialAdd,.polynomialSubtract,.polynomialMultiply,.polynomialDivide,.equivalent].contains(operation) }
    static func compute(_ request:MathComputationRequest) async throws->MathComputationAnswer {
        let reply=try await Calc1WorkerRunner().run(request)
        return MathComputationAnswer(request:reply.resolved ?? request,inputLatex:request.inputA,outputLatex:reply.latex ?? "",steps:reply.steps ?? [],engineVersion:version)
    }
    static func inspect(_ request:MathComputationRequest) async throws->Calc1InputReview {
        let reply=try await Calc1WorkerRunner().run(request,inspect:true)
        guard let review=reply.review else { throw PolynomialError.invalid("No expression preview was produced.") }
        return review
    }
}

/// Every request owns a fresh worker, so rows never share CAS variables/history.
/// The worker has an 8s JS deadline; the native watchdog also covers web loading.
@MainActor
final class Calc1WorkerRunner:NSObject,WKScriptMessageHandler,WKNavigationDelegate {
    struct Reply:Decodable,Sendable {
        let ok:Bool
        let error:String?
        let latex:String?
        let steps:[String]?
        let resolved:MathComputationRequest?
        let review:Calc1InputReview?
    }
    private var continuation:CheckedContinuation<Reply,Error>?
    private var browser:WKWebView?
    private var window:UIWindow?
    private var watchdog:Task<Void,Never>?
    private var requestJSON=""
    private var workerSource=""
    private var deadlineMS=8000
#if DEBUG
    var testWorkerSource:String?
    var testDeadlineMS:Int?
#endif
    func run(_ request:MathComputationRequest,inspect:Bool=false) async throws->Reply {
        try Task.checkCancellation()
        guard let vendor=Bundle.main.url(forResource:"nerdamer-2.0.1",withExtension:"js"),let worker=Bundle.main.url(forResource:"calc1-worker",withExtension:"js") else { throw PolynomialError.invalid("The bundled calculus engine is unavailable.") }
        workerSource=try String(contentsOf:vendor,encoding:.utf8)+"\n"+String(contentsOf:worker,encoding:.utf8)
#if DEBUG
        if let testWorkerSource { workerSource=testWorkerSource }
        if let testDeadlineMS { deadlineMS=testDeadlineMS }
#endif
        let data=Data(try request.encoded().utf8)
        var object=try JSONSerialization.jsonObject(with:data) as! [String:Any]
        if inspect { object["operation"]="inspect";object["inspectionOperation"]=request.operation.rawValue }
        requestJSON=String(decoding:try JSONSerialization.data(withJSONObject:object),as:UTF8.self)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation=continuation
                if Task.isCancelled { finish(.failure(CancellationError()));return }
                start()
            }
        } onCancel: { Task { @MainActor in self.finish(.failure(CancellationError())) } }
    }
    private func start() {
        let controller=WKUserContentController();controller.add(self,name:"calculus")
        let configuration=WKWebViewConfiguration();configuration.userContentController=controller
        configuration.websiteDataStore = .nonPersistent()
        let view=WKWebView(frame:CGRect(x:0,y:0,width:8,height:8),configuration:configuration)
        view.navigationDelegate=self;browser=view
        guard let scene=UIApplication.shared.connectedScenes.compactMap({$0 as? UIWindowScene}).first else { finish(.failure(PolynomialError.invalid("Open a notebook before computing.")));return }
        let window=UIWindow(windowScene:scene);window.frame=view.frame
        window.windowLevel=UIWindow.Level(rawValue:UIWindow.Level.normal.rawValue-2)
        window.rootViewController=UIViewController();window.rootViewController!.view.addSubview(view);window.isHidden=false;self.window=window
        watchdog=Task { @MainActor in
            do { try await Task.sleep(for:.seconds(12));try Task.checkCancellation();finish(.failure(PolynomialError.invalid("The computation timed out. Try a smaller expression."))) } catch { }
        }
        view.loadHTMLString(Self.html,baseURL:nil)
    }
    func webView(_ webView:WKWebView,didFinish navigation:WKNavigation!) {
        guard continuation != nil else { return }
        let source=workerSource,json=requestJSON,deadline=deadlineMS
        Task { @MainActor in
            do { _=try await webView.callAsyncJavaScript("window.startMath(source, JSON.parse(request), deadline);",arguments:["source":source,"request":json,"deadline":deadline],in:nil,contentWorld:.page) }
            catch { finish(.failure(error)) }
        }
    }
    func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage) {
        guard let text=message.body as? String,text.utf8.count<=100_000,let data=text.data(using:.utf8) else { finish(.failure(PolynomialError.invalid("The computation returned an invalid response.")));return }
        do { let reply=try JSONDecoder().decode(Reply.self,from:data)
            if reply.ok { finish(.success(reply)) }
            else { finish(.failure(PolynomialError.invalid(reply.error ?? "The expression is unsupported."))) }
        } catch { finish(.failure(error)) }
    }
    func webViewWebContentProcessDidTerminate(_ webView:WKWebView) { finish(.failure(PolynomialError.invalid("The math process stopped. Try a smaller expression."))) }
    func webView(_ webView:WKWebView,didFailProvisionalNavigation navigation:WKNavigation!,withError error:Error) { finish(.failure(error)) }
    func webView(_ webView:WKWebView,didFail navigation:WKNavigation!,withError error:Error) { finish(.failure(error)) }
    private func finish(_ result:Result<Reply,Error>) {
        guard let continuation else { return };self.continuation=nil
        watchdog?.cancel();watchdog=nil
        browser?.evaluateJavaScript("window.cancelMath && window.cancelMath()",completionHandler:nil)
        browser?.configuration.userContentController.removeScriptMessageHandler(forName:"calculus")
        browser?.navigationDelegate=nil;browser?.stopLoading();browser?.removeFromSuperview();browser=nil
        window?.isHidden=true;window=nil;workerSource="";requestJSON=""
        continuation.resume(with:result)
    }
    private static let html=#"""
    <!doctype html><html><head><meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'unsafe-inline'; worker-src blob:; connect-src 'none'"></head><body><script>
    let worker=null, timer=null, url=null;
    window.cancelMath=()=>{if(worker)worker.terminate();worker=null;clearTimeout(timer);if(url)URL.revokeObjectURL(url);url=null;};
    window.startMath=(source,request,deadline)=>{
      window.cancelMath();url=URL.createObjectURL(new Blob([source],{type:'application/javascript'}));
      const done=result=>{window.cancelMath();window.webkit.messageHandlers.calculus.postMessage(JSON.stringify(result));};
      try {worker=new Worker(url);worker.onmessage=e=>done(e.data);worker.onerror=e=>done({ok:false,error:'The math worker failed: '+e.message});timer=setTimeout(()=>done({ok:false,error:'The computation exceeded its time limit. Try a smaller expression.'}),deadline);worker.postMessage(request);}
      catch(e){done({ok:false,error:e.message});}
    };
    </script></body></html>
    """#
}
