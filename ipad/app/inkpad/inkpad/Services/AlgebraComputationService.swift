import Foundation

nonisolated extension PolynomialValue {
    func division(by divisor:Self) throws -> (quotient:Self,remainder:Self) {
        guard !divisor.coefficients.isEmpty else { throw PolynomialError.invalid("Cannot divide by the zero polynomial.") }
        var quotient=Self.zero,remainder=self
        for _ in 0...20 {
            try Task.checkCancellation()
            guard !remainder.coefficients.isEmpty,remainder.degree>=divisor.degree else { return (quotient,remainder) }
            let term=Self([remainder.degree-divisor.degree:try remainder.coefficients[remainder.degree]!.dividing(divisor.coefficients[divisor.degree]!)])
            quotient=try quotient.adding(term)
            remainder=try remainder.adding(divisor.multiplying(term).negated())
        }
        throw PolynomialError.invalid("Polynomial division exceeded the supported degree.")
    }
}

nonisolated struct AlgebraComputationService {
    private let polynomial=PolynomialIntegrationService()
    func prepared(_ input:String) throws -> PreparedPolynomialIntegral {
        guard !input.contains("\\int"),!input.contains("∫") else { throw PolynomialError.invalid("Enter an algebraic expression without an integral sign.") }
        return try polynomial.prepare(input)
    }
    func suggestedVariable(_ input:String)->String? {
        let parts=input.components(separatedBy:"=")
        let variables=Set(parts.compactMap {try? prepared($0).inferredVariable})
        return variables.count==1 ? variables.first:nil
    }
    private func validate(_ values:[PreparedPolynomialIntegral],variable:String) throws {
        let variables=Set(values.compactMap(\.inferredVariable))
        guard variable.count==1,let c=variable.first,c.isASCII,c.isLetter,variables.count<=1,
              variables.isEmpty || variables.first==variable else { throw PolynomialError.invalid("Use the same single Latin-letter variable in both inputs and the Variable field.") }
    }
    func compute(_ request:MathComputationRequest) throws -> MathComputationAnswer {
        try Task.checkCancellation()
        if request.operation.isNativeAlgebraExtension {return try extended(request)}
        if request.operation == .solveEquation { return try solve(request) }
        let a=try prepared(request.inputA)
        if request.operation != .arithmetic { try validate([a],variable:request.variable) }
        let v=request.variable,output:String,steps:[String]
        switch request.operation {
        case .arithmetic:
            guard a.inferredVariable==nil else { throw PolynomialError.invalid("Arithmetic accepts numeric expressions only; use algebra operations for variables.") }
            output=a.integrand.constant.latex;steps=["Evaluate parentheses, integer powers, multiplication/division and addition/subtraction using exact fractions."]
        case .simplify:output=a.integrand.latex(variable:v);steps=["Expand supported polynomial products, combine like terms and reduce rational coefficients."]
        case .factor:
            let result=try factored(a.integrand,variable:v);output=result.latex;steps=result.steps
        case .polynomialAdd,.polynomialSubtract,.polynomialMultiply,.polynomialDivide,.equivalent:
            let b=try prepared(request.inputB);try validate([a,b],variable:v)
            switch request.operation {
            case .polynomialAdd:output=try a.integrand.adding(b.integrand).latex(variable:v);steps=["Add coefficients of equal powers."]
            case .polynomialSubtract:output=try a.integrand.adding(b.integrand.negated()).latex(variable:v);steps=["Subtract coefficients of equal powers."]
            case .polynomialMultiply:output=try a.integrand.multiplying(b.integrand).latex(variable:v);steps=["Distribute the products and collect equal powers."]
            case .equivalent:
                output=a.integrand==b.integrand ? "\\text{Equivalent}":"\\text{Not equivalent}"
                steps=["Normalize both polynomial expressions with exact rational coefficients.","Compare every coefficient; this is identity checking, not equality at one sample point."]
            default:
                let divided=try a.integrand.division(by:b.integrand)
                guard try divided.quotient.multiplying(b.integrand).adding(divided.remainder)==a.integrand else { throw PolynomialError.invalid("Division verification failed.") }
                let q=divided.quotient.latex(variable:v),r=divided.remainder.latex(variable:v),d=b.integrand.latex(variable:v)
                output=divided.remainder.coefficients.isEmpty ? q:(divided.quotient.coefficients.isEmpty ? "":"\\left("+q+"\\right) + ")+"\\frac{"+r+"}{"+d+"}"
                steps=["Polynomial long division.","Quotient: "+q,"Remainder: "+r,"Verified dividend = divisor × quotient + remainder.","The original divisor must be nonzero; denominator exclusions remain in force."]
            }
        default:throw PolynomialError.invalid("Choose an algebra operation.")
        }
        return MathComputationAnswer(request:request,inputLatex:request.inputA,outputLatex:output,steps:steps)
    }
    private func solve(_ request:MathComputationRequest) throws -> MathComputationAnswer {
        let parts=request.inputA.components(separatedBy:"=")
        guard (1...2).contains(parts.count),!parts[0].trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { throw PolynomialError.invalid("Enter one equation, such as 2x+3=11, or an expression to set equal to zero.") }
        let lhs=try prepared(parts[0]),rhs=try prepared(parts.count==2 ? parts[1]:"0")
        try validate([lhs,rhs],variable:request.variable)
        let p=try lhs.integrand.adding(rhs.integrand.negated()),v=request.variable
        guard p.degree<=2 else { throw PolynomialError.invalid("Equation solving currently supports linear and quadratic polynomials. Higher-degree equations are not silently approximated.") }
        var steps=["Move both sides to the left: "+p.latex(variable:v)+" = 0."]
        let output:String
        let a=p.coefficients[2] ?? .zero,b=p.coefficients[1] ?? .zero,c=p.constant
        if a.numerator==0 {
            if b.numerator==0 {
                output=c.numerator==0 ? v+" \\in \\mathbb{C}":"\\varnothing"
                steps.append(c.numerator==0 ? "Identity: every complex value is a solution.":"Contradiction: there is no solution.")
            } else {
                let root=try c.negated().dividing(b);output=v+" = "+root.latex
                steps.append("Isolate the variable using exact division.")
                guard try MathComputationService().evaluate(p,at:root) == .zero else { throw PolynomialError.invalid("Solution verification failed.") }
                steps.append("Verified by exact substitution into the original difference.")
            }
        } else {
            let discriminant=try b.multiplying(b).adding(ExactRational(4).multiplying(a).multiplying(c).negated())
            steps.append("Discriminant b² − 4ac = "+discriminant.plain+".")
            if discriminant.numerator<0 {
                // Represent roots as r ± i sqrt(s). Verify real and imaginary
                // coefficients exactly, without evaluating complex strings.
                let denominator=try ExactRational(2).multiplying(a)
                let real=try b.negated().dividing(denominator)
                let square=try discriminant.negated().dividing(denominator.multiplying(denominator))
                let imaginaryResidual=try denominator.multiplying(real).adding(b)
                let realResidual=try a.multiplying(real.multiplying(real).adding(square.negated())).adding(b.multiplying(real)).adding(c)
                guard imaginaryResidual == .zero,realResidual == .zero else { throw PolynomialError.invalid("Complex root verification failed.") }
                let imaginary=try radicalMagnitude(square,imaginary:true)
                output=v+" = "+(real == .zero ? "\\pm ":real.latex+" \\pm ")+imaginary
                steps.append("Complex conjugate roots: the negative discriminant gives two non-real solutions.")
                steps.append("Apply the quadratic formula with i² = −1. Both roots were verified by exact real and imaginary coefficient identities.")
            }
            else {
                let denominator=try ExactRational(2).multiplying(a),negativeB=try b.negated()
                if let squareRoot=try rationalSquareRoot(discriminant) {
                    let first=try negativeB.adding(squareRoot).dividing(denominator),second=try negativeB.adding(squareRoot.negated()).dividing(denominator)
                    guard try MathComputationService().evaluate(p,at:first) == .zero,try MathComputationService().evaluate(p,at:second) == .zero else { throw PolynomialError.invalid("Quadratic solution verification failed.") }
                    output=first==second ? v+" = "+first.latex:v+" \\in \\left\\{"+first.latex+", "+second.latex+"\\right\\}"
                    steps.append("Apply the quadratic formula and verify both roots by exact substitution.")
                } else {
                    output=v+" = \\frac{"+negativeB.latex+" \\pm \\sqrt{"+discriminant.latex+"}}{"+denominator.latex+"}"
                    steps.append("Apply the quadratic formula. Irrational roots remain exact radicals; no decimal approximation is substituted.")
                }
            }
        }
        return MathComputationAnswer(request:request,inputLatex:request.inputA,outputLatex:output,steps:steps)
    }
    /// Bounded square-factor extraction; an unfinished factor remains an
    /// exact radical rather than a guessed simplification.
    private func radicalMagnitude(_ square:ExactRational,imaginary:Bool) throws -> String {
        if let root=try rationalSquareRoot(square) {
            return (root == .one ? (imaginary ? "":"1"):root.latex+(imaginary ? "\\,":""))+(imaginary ? "i":"")
        }
        func extract(_ value:Int64) throws -> (Int64,Int64) {
            var remaining=value,outside:Int64=1,factor:Int64=2
            while factor<=remaining/factor && factor<=10_000 {
                try Task.checkCancellation()
                let squared=factor*factor
                while remaining%squared==0 { outside *= factor;remaining /= squared }
                factor += 1
            }
            return (outside,remaining)
        }
        let (n,nr)=try extract(square.numerator),(d,dr)=try extract(square.denominator)
        let coefficient=try ExactRational(n,d)
        let radicand=try ExactRational(nr,dr)
        return (coefficient == .one ? "":coefficient.latex+"\\,")+(imaginary ? "i":"")+"\\sqrt{"+radicand.latex+"}"
    }
    func rationalSquareRoot(_ value:ExactRational) throws -> ExactRational? {
        func root(_ n:Int64)->Int64? {
            guard n>=0 else {return nil};var low:Int64=0,high=min(n,3_037_000_499)
            while low<=high {let mid=low+(high-low)/2,square=mid*mid;if square==n{return mid};if square<n{low=mid+1}else{high=mid-1}}
            return nil
        }
        guard let numerator=root(value.numerator),let denominator=root(value.denominator) else {return nil}
        return try ExactRational(numerator,denominator)
    }
    /// This batch is native and exact. Its grammar is deliberately narrower
    /// than the elementary calculus adapter, and has no fallback to sampling.
    func extensionVariable(_ request:MathComputationRequest)throws->String {
        guard ([request.inputA]+(request.operation.needsB ? [request.inputB]:[])).allSatisfy({$0.range(of:#"[0-9](?:\.[0-9]*)?[eE][+-]?[0-9]"#,options:.regularExpression)==nil}) else {
            throw PolynomialError.invalid("Use decimal or fraction coefficients for this exact algebra command; scientific notation is not supported here.")
        }
        if request.operation.isComplex { _=try ExactComplexValue.parse(request.inputA);return "x" }
        let expressions:[String]
        switch request.operation {
        case .solveInequality:let p=try inequalityParts(request.inputA);expressions=[p.0,p.2]
        case .solveAbsolute:let p=try absoluteParts(request.inputA);expressions=[p.0,p.1]
        default:expressions=[request.inputA,request.inputB]
        }
        let values=try expressions.map{try prepared($0)}
        let variables=Set(values.compactMap(\.inferredVariable))
        guard variables.count<=1,!variables.contains("e"),!variables.contains("i") else {throw PolynomialError.invalid("Use one real variable such as x or t; e and i are reserved constants.")}
        return variables.first ?? request.variable
    }
    private func extended(_ original:MathComputationRequest)throws->MathComputationAnswer {
        var q=original;q.variable=try extensionVariable(q)
        let output:String,steps:[String]
        switch q.operation {
        case .complexCalculate,.complexConjugate,.complexModulus:
            let z=try ExactComplexValue.parse(q.inputA)
            if q.operation == .complexCalculate {output=z.latex;steps=["Calculate with exact rational real and imaginary parts, using i² = −1.","Complex division uses the conjugate and rejects division by zero."]}
            else if q.operation == .complexConjugate {output=try z.conjugated().latex;steps=["Change the sign of the imaginary part; keep the real part unchanged."]}
            else {let n=try z.normSquared;output=try rationalSquareRoot(n)?.latex ?? "\\sqrt{"+n.latex+"}";steps=["The modulus is the nonnegative real number √(a²+b²), for z=a+bi."]}
        case .compose:
            let a=try prepared(q.inputA),b=try prepared(q.inputB);try validate([a,b],variable:q.variable)
            var result=PolynomialValue.zero
            for (degree,coefficient) in a.integrand.coefficients {
                let term=degree==0 ? PolynomialValue([0:coefficient]):try b.integrand.power(degree).multiplying(PolynomialValue([0:coefficient]))
                result=try result.adding(term)
            }
            output=result.latex(variable:q.variable)
            steps=["Compose A(B(\(q.variable))): substitute all of expression B for the variable in A, then expand and collect terms.","The order matters. This command supports single-variable polynomials with result degree at most 20."]
        case .solveAbsolute:
            let parts=try absoluteParts(q.inputA),left=try prepared(parts.0),right=try prepared(parts.1)
            try validate([left,right],variable:q.variable)
            guard left.integrand.degree<=1,right.integrand.isConstant else {throw PolynomialError.invalid("Use |a·x+b|=c with a constant right side, for example |2x-3|=5. Higher-degree or shifted absolute-value equations are not supported yet.")}
            let a=left.integrand.coefficients[1] ?? .zero,b=left.integrand.constant,c=right.integrand.constant
            if c.numerator<0 {output="\\varnothing"}
            else if a == .zero {let magnitude=try b.numerator<0 ? b.negated():b;output=magnitude==c ? q.variable+" \\in \\mathbb{R}":"\\varnothing"}
            else {
                let first=try c.adding(b.negated()).dividing(a),second=try c.negated().adding(b.negated()).dividing(a)
                for root in [first,second] {let v=try MathComputationService().evaluate(left.integrand,at:root);guard (try v.numerator<0 ? v.negated():v)==c else {throw PolynomialError.invalid("Absolute-value solution verification failed.")}}
                output=first==second ? q.variable+" = "+first.latex:q.variable+" \\in \\left\\{"+first.latex+", "+second.latex+"\\right\\}"
            }
            steps=["Solve over the real numbers. An absolute value cannot equal a negative number.","For a nonnegative right side c, solve ax+b=c and ax+b=−c; remove duplicate roots.","Every returned finite root was checked in the original absolute-value equation."]
        case .solveInequality:
            let parts=try inequalityParts(q.inputA),a=try prepared(parts.0),b=try prepared(parts.2);try validate([a,b],variable:q.variable)
            let p=try a.integrand.adding(b.integrand.negated())
            guard p.degree<=2 else {throw PolynomialError.invalid("Exact inequalities currently support linear and quadratic polynomials. Rational, higher-degree and chained inequalities need a separate method.")}
            output=try inequality(p,op:parts.1,variable:q.variable)
            steps=["Solve over the real numbers after moving both sides to the left: "+p.latex(variable:q.variable)+" "+parts.1+" 0.","Use exact critical roots and the linear/quadratic sign pattern. Strict inequalities exclude roots; ≤ and ≥ include them.","Intervals are exact, not sampled or rounded. This operation does not support variable denominators or chained inequalities."]
        default:throw PolynomialError.invalid("Choose a supported exact algebra operation.")
        }
        return MathComputationAnswer(request:q,inputLatex:q.inputA,outputLatex:output,steps:steps)
    }
    func inequalityParts(_ input:String)throws->(String,String,String) {
        var text=input
        for (a,b) in [("\\leq","<="),("\\geq",">="),("\\le","<="),("\\ge",">="),("≤","<="),("≥",">=")] {text=text.replacingOccurrences(of:a,with:b)}
        let regex=try NSRegularExpression(pattern:#"^\s*([^<>=]+)(<=|>=|<|>)([^<>=]+)\s*$"#)
        let ns=text as NSString
        guard let m=regex.firstMatch(in:text,range:NSRange(location:0,length:ns.length)) else {throw PolynomialError.invalid("Enter one inequality, such as x²-1≤0 or 2x+3>7. Use <= or >= when typing.")}
        return (ns.substring(with:m.range(at:1)),ns.substring(with:m.range(at:2)),ns.substring(with:m.range(at:3)))
    }
    func absoluteParts(_ input:String)throws->(String,String) {
        var text=input.replacingOccurrences(of:" ",with:"").replacingOccurrences(of:"\\left",with:"").replacingOccurrences(of:"\\right",with:"")
        for command in ["\\lvert","\\rvert","\\vert"] {text=text.replacingOccurrences(of:command,with:"|")}
        let parts=text.components(separatedBy:"=")
        guard parts.count==2 else {throw PolynomialError.invalid("Enter |a·x+b|=c, such as |2x-3|=5.")}
        let lhs=parts[0],inside:String
        if lhs.hasPrefix("|"),lhs.hasSuffix("|"),lhs.count>2 {inside=String(lhs.dropFirst().dropLast())}
        else if lhs.hasPrefix("abs("),lhs.hasSuffix(")") {inside=String(lhs.dropFirst(4).dropLast())}
        else {throw PolynomialError.invalid("Put the absolute value alone on the left, for example |2x-3|=5 or abs(2x-3)=5.")}
        return (inside,parts[1])
    }
    private func inequality(_ p:PolynomialValue,op:String,variable:String)throws->String {
        let inclusive=op.contains("="),desired=op.hasPrefix("<") ? -1:1
        let all=variable+" \\in \\mathbb{R}",none="\\varnothing"
        func interval(_ lo:String?,_ hi:String?,_ include:Bool)->String {
            (lo != nil && include ? "\\left[":"\\left(")+(lo ?? "-\\infty")+", "+(hi ?? "\\infty")+(hi != nil && include ? "\\right]":"\\right)")
        }
        func outside(_ lo:String,_ hi:String,_ include:Bool)->String {interval(nil,lo,include)+" \\cup "+interval(hi,nil,include)}
        func sign(_ r:ExactRational)->Int {r.numerator==0 ? 0:r.numerator>0 ? 1:-1}
        if p.isConstant {let s=sign(p.constant);return s==desired || s==0 && inclusive ? all:none}
        let a=p.coefficients[2] ?? .zero,b=p.coefficients[1] ?? .zero,c=p.constant
        if a == .zero {
            let root=try c.negated().dividing(b).latex
            return variable+" \\in "+(sign(b)==desired ? interval(root,nil,inclusive):interval(nil,root,inclusive))
        }
        let d=try b.multiplying(b).adding(ExactRational(4).multiplying(a).multiplying(c).negated())
        if d.numerator<0 {return sign(a)==desired ? all:none}
        let den=try ExactRational(2).multiplying(a),center=try b.negated().dividing(den)
        if d == .zero {
            if sign(a)==desired {return inclusive ? all:variable+" \\in "+outside(center.latex,center.latex,false)}
            return inclusive ? variable+" = "+center.latex:none
        }
        let square=try d.dividing(den.multiplying(den)),lo:String,hi:String
        if let offset=try rationalSquareRoot(square) {lo=try center.adding(offset.negated()).latex;hi=try center.adding(offset).latex}
        else {let offset=try radicalMagnitude(square,imaginary:false);lo=(center == .zero ? "-":center.latex+" - ")+offset;hi=(center == .zero ? "":center.latex+" + ")+offset}
        return variable+" \\in "+(sign(a)==desired ? outside(lo,hi,inclusive):interval(lo,hi,inclusive))
    }
    private func factored(_ original:PolynomialValue,variable:String) throws -> (latex:String,steps:[String]) {
        if original.isConstant {return (original.latex(variable:variable),["A constant polynomial needs no linear factorization."])}
        var remaining=original,factors:[PolynomialValue]=[],steps:[String]=[],skipped=false
        while !remaining.isConstant {
            try Task.checkCancellation()
            if remaining.constant.numerator==0 {
                factors.append(.variable);remaining=try remaining.division(by:.variable).quotient;steps.append("Extract a factor of "+variable+".");continue
            }
            if remaining.degree==1 {factors.append(remaining);remaining=PolynomialValue([0:.one]);break}
            let candidates=try rationalCandidates(remaining)
            var found:ExactRational?
            for candidate in candidates {
                try Task.checkCancellation()
                do {if try MathComputationService().evaluate(remaining,at:candidate) == .zero{found=candidate;break}}
                catch is CancellationError {throw CancellationError()}
                catch {skipped=true}
            }
            guard let root=found else {break}
            let linear=PolynomialValue([1:.one,0:try root.negated()])
            let divided=try remaining.division(by:linear)
            guard divided.remainder == .zero else {throw PolynomialError.invalid("Factor verification failed.")}
            factors.append(linear);remaining=divided.quotient;steps.append("Root "+root.plain+" gives factor ("+linear.latex(variable:variable)+").")
        }
        var verification=remaining
        for factor in factors {verification=try verification.multiplying(factor)}
        guard verification==original else {throw PolynomialError.invalid("Factorization verification failed.")}
        var pieces=factors.map {"\\left("+$0.latex(variable:variable)+"\\right)"}
        if !remaining.isConstant || remaining.constant != .one || pieces.isEmpty {
            pieces.insert(remaining.isConstant ? remaining.latex(variable:variable):"\\left("+remaining.latex(variable:variable)+"\\right)",at:0)
        }
        if !remaining.isConstant {steps.append("Remaining factor is retained exactly. This operation searches rational linear factors, not every higher-degree factorization.")}
        if skipped {steps.append("Some candidate evaluations exceeded exact-number limits; remaining factors are not claimed irreducible.")}
        steps.append("Verified by multiplying the factors back to the original polynomial.")
        return (pieces.joined(separator:" \\cdot "),steps)
    }
    private func rationalCandidates(_ p:PolynomialValue) throws -> [ExactRational] {
        func gcd(_ a:Int64,_ b:Int64)->Int64 {var a=a,b=b;while b != 0{let r=a%b;a=b;b=r};return max(a,1)}
        var common:Int64=1
        for c in p.coefficients.values {
            let result=(common/gcd(common,c.denominator)).multipliedReportingOverflow(by:c.denominator)
            guard !result.overflow else {throw PolynomialError.invalid("Coefficients are too large for exact rational-root search.")};common=result.partialValue
        }
        var integers:[Int:Int64]=[:]
        for (degree,c) in p.coefficients {
            let n=c.numerator.multipliedReportingOverflow(by:common/c.denominator)
            guard !n.overflow,n.partialValue != .min else {throw PolynomialError.invalid("Coefficients are too large for exact rational-root search.")};integers[degree]=n.partialValue
        }
        let divisor=integers.values.reduce(Int64(0)){gcd(abs($0),abs($1))}
        let constant=abs(integers[0]!/max(divisor,1)),leading=abs(integers[p.degree]!/max(divisor,1))
        func divisors(_ n:Int64) throws -> [Int64] {
            guard n<=100_000_000 else {throw PolynomialError.invalid("Rational factor search supports primitive leading/constant coefficients up to 100,000,000.")}
            var result:[Int64]=[],i:Int64=1
            while i<=n/i {try Task.checkCancellation();if n%i==0{result.append(i);if i != n/i{result.append(n/i)}};i+=1}
            return result.sorted()
        }
        let tops=try divisors(constant),bottoms=try divisors(leading)
        guard tops.count*bottoms.count<=4096 else {throw PolynomialError.invalid("This polynomial has too many rational-root candidates; use smaller coefficients.")}
        var result:[ExactRational]=[]
        for top in tops {for bottom in bottoms where gcd(top,bottom)==1 {let value=try ExactRational(top,bottom);result.append(value);result.append(try value.negated())}}
        return result
    }
}
