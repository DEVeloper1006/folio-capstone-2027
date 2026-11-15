import Foundation

/// Parses the outer integral notation; the existing bounded polynomial parser
/// validates the integrand, differential, variable and polynomial structure.
nonisolated struct PolynomialIntegralInput:Sendable {
    let prepared:PreparedPolynomialIntegral
    let lower:String?
    let upper:String?
    var variable:String { prepared.suggestedVariable }
    var isDefinite:Bool { lower != nil && upper != nil }
    static func hasIntegral(_ input:String)->Bool { input.contains("\\int") || input.contains("∫") }
    static func parse(_ input:String)throws->Self {
        var text=input.trimmingCharacters(in:.whitespacesAndNewlines)
        guard text.count<=5000 else { throw PolynomialError.invalid("Use an integral of at most 5,000 characters.") }
        for (open,close) in [("\\[","\\]"),("\\(","\\)"),("$$","$$"),("$","$")] {
            if text.hasPrefix(open),text.hasSuffix(close),text.count>=open.count+close.count {
                text=String(text.dropFirst(open.count).dropLast(close.count)).trimmingCharacters(in:.whitespacesAndNewlines);break
            }
        }
        for command in ["\\displaystyle","\\textstyle"] where text.hasPrefix(command) {
            text=String(text.dropFirst(command.count)).trimmingCharacters(in:.whitespacesAndNewlines)
        }
        var cursor=IntegralCursor(text)
        if !cursor.consume("\\int") && !cursor.consume("∫") { throw PolynomialError.invalid("Enter one full integral, starting with ∫ or \\int.") }
        cursor.skipSpaces()
        if cursor.consume("\\limits") || cursor.consume("\\nolimits") { cursor.skipSpaces() }
        var lower:String?,upper:String?
        while let marker=cursor.current,marker == "_" || marker == "^" {
            cursor.advance();let bound=try cursor.bound()
            if marker == "_" {
                guard lower==nil else { throw PolynomialError.invalid("The integral has more than one lower bound.") };lower=bound
            } else {
                guard upper==nil else { throw PolynomialError.invalid("The integral has more than one upper bound.") };upper=bound
            }
            cursor.skipSpaces()
        }
        guard (lower==nil)==(upper==nil) else { throw PolynomialError.invalid("The integral needs both a lower and an upper bound. Review the recognized limits, e.g. \\int_{0}^{1} x^2\\,dx.") }
        if let lower { _=try numericBound(lower,label:"Lower") }
        if let upper { _=try numericBound(upper,label:"Upper") }
        let rest=cursor.remaining.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !rest.isEmpty else { throw PolynomialError.invalid("The integral is missing its polynomial and differential, e.g. x^2 dx.") }
        let prepared:PreparedPolynomialIntegral
        do { prepared=try PolynomialIntegrationService().prepare("\\int "+rest) }
        catch { throw PolynomialError.invalid("Review the integrand and differential (dx, dt, etc.). "+error.localizedDescription) }
        return Self(prepared:prepared,lower:lower,upper:upper)
    }
    static func numericBound(_ text:String,label:String)throws->ExactRational {
        do {
            var value=text.trimmingCharacters(in:.whitespacesAndNewlines)
            let negative=value.hasPrefix("-") || value.hasPrefix("−")
            if negative || value.hasPrefix("+") { value.removeFirst();value=value.trimmingCharacters(in:.whitespacesAndNewlines) }
            let scalar=try ExactRational.scalar(value)
            return negative ? try scalar.negated():scalar
        }
        catch { throw PolynomialError.invalid("\(label) bound must be an integer, decimal or numeric fraction, such as -1, 0.5 or \\frac{1}{2}. Symbolic and infinite limits are not supported. "+error.localizedDescription) }
    }
    static func resolved(_ request:MathComputationRequest)throws->MathComputationRequest {
        guard [.integral,.definiteIntegral].contains(request.operation),hasIntegral(request.inputA) else { return request }
        let integral=try parse(request.inputA)
        if integral.isDefinite && request.operation != .definiteIntegral {
            throw PolynomialError.invalid("This integral has bounds. Choose Definite polynomial integral to evaluate them.")
        }
        var result=request;result.variable=integral.variable
        if let lower=integral.lower,let upper=integral.upper { result.lower=lower;result.upper=upper }
        return result
    }
}

private nonisolated struct IntegralCursor {
    private var characters:[Character]
    private var index=0
    init(_ text:String) { characters=Array(text) }
    var current:Character? { index<characters.count ? characters[index]:nil }
    var remaining:String { String(characters[index...]) }
    mutating func advance() { index+=1 }
    mutating func skipSpaces() { while current?.isWhitespace==true { advance() } }
    mutating func consume(_ text:String)->Bool {
        let value=Array(text)
        guard index+value.count<=characters.count,Array(characters[index..<index+value.count])==value else { return false }
        index+=value.count;return true
    }
    mutating func bound()throws->String {
        skipSpaces()
        if current=="{" {
            advance();let start=index;var depth=1
            while let c=current {
                if c=="{" { depth+=1 };if c=="}" { depth-=1 }
                if depth==0 { let value=String(characters[start..<index]);advance();guard !value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw PolynomialError.invalid("An integral bound is empty.") };return value }
                advance()
            }
            throw PolynomialError.invalid("An integral bound has an unclosed brace. Review its lower and upper limits.")
        }
        let start=index
        if current=="-" || current=="−" || current=="+" { advance() }
        while let c=current,c.isASCII && (c.isNumber || c==".") { advance() }
        guard index>start,characters[start..<index].contains(where:{$0.isNumber}) else {
            throw PolynomialError.invalid("Put each bound in braces, e.g. _{-1}^{2} or _{0}^{\\frac{1}{2}}.")
        }
        return String(characters[start..<index])
    }
}
