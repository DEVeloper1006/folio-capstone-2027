/* Classifies worksheet statements without discarding function signatures, prime notation, derivative operators or integration differentials. Original transcriptions remain untouched. */
import Foundation

nonisolated struct WorksheetMathNotation:Codable,Sendable {
    enum Kind:String,Codable { case definition,equation,expression,derivative,partial,integral }
    let input:String
    let text:String
    let kind:Kind
    let name:String?
    let arguments:[String]
    let body:String
    let variable:String?
    let order:Int
    let numbered:Bool
    let expressionAST:PolynomialAST?

    /// Store semantic notation together with the bounded native expression tree when its grammar applies; calculus operators retain their typed fields.
    init(input:String,text:String,kind:Kind,name:String?,arguments:[String],body:String,variable:String?,order:Int,numbered:Bool) {
        self.input=input;self.text=text;self.kind=kind;self.name=name;self.arguments=arguments
        self.body=body;self.variable=variable;self.order=order;self.numbered=numbered
        expressionAST=try? PolynomialIntegrationService().expressionAST(body)
    }

    /// Return regex capture groups only for a complete grammar match; matching never evaluates source text.
    static func captures(_ pattern:String,_ text:String)->[String]? {
        guard let regex=try? NSRegularExpression(pattern:pattern),let match=regex.firstMatch(in:text,range:NSRange(text.startIndex...,in:text)) else { return nil }
        return (1..<match.numberOfRanges).map { index in Range(match.range(at:index),in:text).map{String(text[$0])} ?? "" }
    }

    /// Normalize display variants while preserving primes, partial symbols and differentials as semantic notation.
    static func normalized(_ input:String)->String {
        input.trimmingCharacters(in:.whitespacesAndNewlines)
            .replacingOccurrences(of:"\\left",with:"").replacingOccurrences(of:"\\right",with:"")
            .replacingOccurrences(of:"′",with:"'").replacingOccurrences(of:"″",with:"''")
            .replacingOccurrences(of:"’",with:"'").replacingOccurrences(of:"‘",with:"'")
            .replacingOccurrences(of:"^{\\prime}",with:"'").replacingOccurrences(of:"\\prime",with:"'")
            .replacingOccurrences(of:"\\mathrm{d}",with:"d").replacingOccurrences(of:"−",with:"-")
    }

    /// Classify definitions, requests and intermediate expressions independently of the solver's operation coverage.
    static func read(_ input:String)throws->Self {
        guard !input.isEmpty,input.count<=5000 else { throw PolynomialError.invalid("Review one math row of at most 5,000 characters.") }
        var text=normalized(input)
        let label=captures(#"^\s*\d+[.)]\s+(.+)$"#,text)
        if let label { text=label[0] }
        let compact=text.filter{!$0.isWhitespace}
        if let m=captures(#"^([A-Za-z])\(([A-Za-z](?:,[A-Za-z])*)\)=(.+)$"#,compact) {
            let args=m[1].split(separator:",").map(String.init)
            guard Set(args).count==args.count else { throw PolynomialError.invalid("Function parameters must be distinct.") }
            return Self(input:input,text:text,kind:.definition,name:m[0],arguments:args,body:m[2],variable:args.first,order:0,numbered:label != nil)
        }
        if let m=captures(#"^([A-Za-z])('{1,2})(?:\(([A-Za-z])\)|([A-Za-z]))?$"#,compact) {
            let v=m[2].isEmpty ? (m[3].isEmpty ? nil:m[3]):m[2]
            return Self(input:input,text:text,kind:.derivative,name:m[0],arguments:[],body:"",variable:v,order:m[1].count,numbered:label != nil)
        }
        let derivativePatterns=[#"^(d|∂|\\partial)([A-Za-z])/(?:d|∂|\\partial)([A-Za-z])$"#,
                                #"^\\(?:d?frac|tfrac)\{(d|∂|\\partial)([A-Za-z])\}\{(?:d|∂|\\partial)([A-Za-z])\}$"#]
        for pattern in derivativePatterns {
            if let m=captures(pattern,compact) {
                return Self(input:input,text:text,kind:m[0]=="d" ? .derivative:.partial,name:m[1],arguments:[],body:"",variable:m[2],order:1,numbered:label != nil)
            }
        }
        if let m=captures(#"^(?:d/d([A-Za-z])|\\frac\{d\}\{d([A-Za-z])\})(.+)$"#,compact) {
            return Self(input:input,text:text,kind:.derivative,name:nil,arguments:[],body:m[2],variable:m[0].isEmpty ? m[1]:m[0],order:1,numbered:label != nil)
        }
        if let m=captures(#"^(?:∂/∂([A-Za-z])|\\frac\{\\partial\}\{\\partial([A-Za-z])\})(.+)$"#,compact) {
            return Self(input:input,text:text,kind:.partial,name:nil,arguments:[],body:m[2],variable:m[0].isEmpty ? m[1]:m[0],order:1,numbered:label != nil)
        }
        if PolynomialIntegralInput.hasIntegral(text) {
            return Self(input:input,text:text,kind:.integral,name:nil,arguments:[],body:text,variable:captures(#"d([A-Za-z])\s*$"#,compact)?.first,order:0,numbered:label != nil)
        }
        let parts=text.components(separatedBy:"=")
        if parts.count==2,let m=captures(#"^\s*([A-Za-z])\s*$"#,parts[0]),!parts[1].isEmpty {
            let name=m[0]
            let variables=(try? PolynomialIntegrationService().expressionAST(parts[1]).variables) ?? Set(parts[1].filter{$0.isASCII && $0.isLetter}.map(String.init))
            return Self(input:input,text:text,kind:variables.contains(name) ? .equation:.definition,name:name,arguments:[],body:parts[1],variable:nil,order:0,numbered:label != nil)
        }
        // Prose and chained equations stay visible but cannot silently become executable definitions.
        guard parts.count<=2,!compact.isEmpty,!compact.contains("\\text"),captures(#"[A-Za-z]{4,}"#,compact)==nil || compact.contains("\\") || compact.contains("(") || ["sinh","cosh","tanh","asin","acos","atan","asinh","acosh","atanh"].contains(where:{compact.hasPrefix($0)}) else {
            throw PolynomialError.invalid("This row needs notation review before computation.")
        }
        return Self(input:input,text:text,kind:parts.count==2 ? .equation:.expression,name:nil,arguments:[],body:text,variable:nil,order:0,numbered:label != nil)
    }

    /// Translate an explicit calculus request or function declaration into a solver request; bare dy remains incomplete notation.
    static func resolved(_ original:MathComputationRequest)throws->MathComputationRequest {
        let notation=try read(original.inputA)
        var result=original
        switch notation.kind {
        case .definition:
            if !notation.arguments.isEmpty || (notation.name=="y" && original.operation.isCalculus) {
                result.inputA=notation.body
                if let variable=notation.variable { result.variable=variable }
            } else { result.inputA=notation.text }
        case .derivative,.partial:
            guard !notation.body.isEmpty else { throw PolynomialError.invalid("This derivative refers to an earlier function. Review its definition in this problem first.") }
            guard original.operation == .derivative || original.operation == .secondDerivative || original.operation == .partialDerivative else { throw PolynomialError.invalid("Choose differentiation for this derivative request.") }
            result.inputA=notation.body;result.variable=notation.variable ?? original.variable
            result.operation=notation.kind == .partial ? .partialDerivative:(notation.order==2 ? .secondDerivative:.derivative)
        default:result.inputA=notation.text
        }
        if captures(#"^d[A-Za-z]$"#,result.inputA) != nil { throw PolynomialError.invalid("A differential such as dy needs an integral or a relation; it is not d multiplied by y.") }
        if result.inputA.range(of:#"[A-Za-z]'|\\partial|∂"#,options:.regularExpression) != nil { throw PolynomialError.invalid("Review the derivative notation. Differential equations and incomplete derivatives are not executable expressions.") }
        return result
    }
}
