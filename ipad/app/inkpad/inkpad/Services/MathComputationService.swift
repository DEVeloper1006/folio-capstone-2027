/* Defines bounded math operations and exact native computations, with an asynchronous dispatcher that preserves original worksheet sources and falls back to isolated calculus execution. */
import Foundation

nonisolated enum MathOperation:String,Codable,CaseIterable,Identifiable,Sendable {
    case rref,rank,determinant,inverse,transpose,matrixAdd,matrixSubtract,matrixMultiply,solve
    case partialDerivative,derivative,expand,evaluate,integral,definiteIntegral
    case arithmetic,simplify,factor,solveEquation,polynomialAdd,polynomialSubtract,polynomialMultiply,polynomialDivide,equivalent
    case solveInequality,solveAbsolute,compose,complexCalculate,complexConjugate,complexModulus
    case trace,matrixScale,matrixPower,nullspace,columnSpace,rowSpace
    case limit,limitLeft,limitRight,secondDerivative,tangentLine,normalLine,implicitDerivative,averageRate,averageValue,numericalIntegral,areaBetween,volumeDisk,volumeShell,volumeWasher,arcLength,rootInterval
    var id:String { rawValue }
    var isComplex:Bool {[.complexCalculate,.complexConjugate,.complexModulus].contains(self)}
    var isNativeAlgebraExtension:Bool {isComplex || [.solveInequality,.solveAbsolute,.compose].contains(self)}
    var isAlgebra:Bool {isNativeAlgebraExtension || [.arithmetic,.simplify,.factor,.solveEquation,.polynomialAdd,.polynomialSubtract,.polynomialMultiply,.polynomialDivide,.equivalent,.areaBetween,.volumeWasher].contains(self)}
    var isCalculus:Bool { [.partialDerivative,.derivative,.expand,.evaluate,.integral,.definiteIntegral,.limit,.limitLeft,.limitRight,.secondDerivative,.tangentLine,.normalLine,.implicitDerivative,.averageRate,.averageValue,.numericalIntegral,.areaBetween,.volumeDisk,.volumeShell,.volumeWasher,.arcLength,.rootInterval].contains(self) }
    var isMatrix:Bool { !isAlgebra && !isCalculus }
    var topic:Int { isMatrix ? 0:(isAlgebra || self == .expand) ? 1:2 }
    var needsInterval:Bool { [.definiteIntegral,.numericalIntegral,.averageRate,.averageValue,.areaBetween,.volumeDisk,.volumeShell,.volumeWasher,.arcLength,.rootInterval].contains(self) }
    var needsPoint:Bool { [.evaluate,.limit,.limitLeft,.limitRight,.tangentLine,.normalLine,.matrixScale,.matrixPower].contains(self) }
    var needsB:Bool { [.compose,.matrixAdd,.matrixSubtract,.matrixMultiply,.polynomialAdd,.polynomialSubtract,.polynomialMultiply,.polynomialDivide,.equivalent,.areaBetween,.volumeWasher].contains(self) }
    var title:String {
        switch self {
        case .solveInequality:"Solve polynomial inequality";case .solveAbsolute:"Solve absolute-value equation";case .compose:"Compose A(B(x))"
        case .complexCalculate:"Calculate complex expression";case .complexConjugate:"Complex conjugate";case .complexModulus:"Complex modulus"
        case .limit:"Limit (two-sided)";case .limitLeft:"Limit from left";case .limitRight:"Limit from right"
        case .secondDerivative:"Second derivative";case .tangentLine:"Tangent line";case .normalLine:"Normal line";case .implicitDerivative:"Implicit dy/dx (x, y)"
        case .averageRate:"Average rate of change";case .averageValue:"Average function value";case .numericalIntegral:"Numerical definite integral"
        case .areaBetween:"Area between curves";case .volumeDisk:"Volume: disks about x-axis";case .volumeShell:"Volume: shells about y-axis";case .volumeWasher:"Volume: washers about x-axis";case .arcLength:"Arc length";case .rootInterval:"Find a root in an interval"
        case .arithmetic:"Calculate";case .simplify:"Simplify";case .factor:"Factor rational linear factors";case .solveEquation:"Solve linear / quadratic equation"
        case .polynomialAdd:"Add polynomials";case .polynomialSubtract:"Subtract polynomials";case .polynomialMultiply:"Multiply polynomials";case .polynomialDivide:"Divide polynomials";case .equivalent:"Check polynomial equivalence"
        case .trace:"Trace";case .matrixScale:"Scale matrix";case .matrixPower:"Integer matrix power";case .nullspace:"Nullspace basis";case .columnSpace:"Column-space basis";case .rowSpace:"Row-space basis"
        case .partialDerivative:"Partial derivative"
        case .rref:"RREF";case .rank:"Rank";case .determinant:"Determinant";case .inverse:"Inverse";case .transpose:"Transpose"
        case .matrixAdd:"Matrix addition";case .matrixSubtract:"Matrix subtraction";case .matrixMultiply:"Matrix multiplication"
        case .solve:"Solve augmented system";case .derivative:"Differentiate";case .expand:"Expand"
        case .evaluate:"Evaluate";case .integral:"Antiderivative";case .definiteIntegral:"Definite integral"
        }
    }
}

nonisolated struct MathComputationRequest:Codable,Equatable,Sendable {
    var operation:MathOperation
    var inputA:String
    var inputB:String = ""
    var variable:String = "x"
    var point:String = "2"
    var lower:String = "0"
    var upper:String = "1"
    func encoded() throws -> String {
        var canonical=self
        canonical.inputA=inputA.trimmingCharacters(in:.whitespacesAndNewlines)
        canonical.inputB=operation.needsB ? inputB.trimmingCharacters(in:.whitespacesAndNewlines):""
        canonical.variable=(operation.isMatrix || operation.isComplex) ? "x":variable.trimmingCharacters(in:.whitespacesAndNewlines)
        canonical.point=operation.needsPoint ? point.trimmingCharacters(in:.whitespacesAndNewlines):"2"
        canonical.lower=operation.needsInterval ? lower.trimmingCharacters(in:.whitespacesAndNewlines):"0"
        canonical.upper=operation.needsInterval ? upper.trimmingCharacters(in:.whitespacesAndNewlines):"1"
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys]
        return String(decoding:try encoder.encode(canonical),as:UTF8.self)
    }
}

nonisolated struct MathComputationAnswer:Sendable {
    let request:MathComputationRequest
    let inputLatex:String
    let outputLatex:String
    let steps:[String]
    var engineVersion:String=MathComputationService.version
}

nonisolated extension ExactRational {
    var plain:String { denominator == 1 ? String(numerator):"\(numerator)/\(denominator)" }
    var latex:String { denominator == 1 ? String(numerator):"\\frac{\(numerator)}{\(denominator)}" }
    static func scalar(_ input:String) throws -> Self {
        var text=input.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !text.isEmpty,text.count<=80 else { throw PolynomialError.invalid("Enter an integer, decimal or fraction in every cell.") }
        text=text.replacingOccurrences(of:"−",with:"-")
            .replacingOccurrences(of:"\\dfrac",with:"\\frac").replacingOccurrences(of:"\\tfrac",with:"\\frac")
        var sign:Self = .one
        if text.hasPrefix("-\\frac") { sign=try Self(-1);text.removeFirst() }
        if text.hasPrefix("\\frac{") {
            guard text.hasSuffix("}"),text.components(separatedBy:"}{").count==2 else { throw PolynomialError.invalid("Use a simple numeric fraction such as 1/2.") }
            let parts=String(text.dropFirst(6).dropLast()).components(separatedBy:"}{")
            text=parts.joined(separator:"/")
        }
        let parts=text.split(separator:"/",omittingEmptySubsequences:false)
        guard parts.count<=2 else { throw PolynomialError.invalid("Use one numeric fraction, such as 1/2.") }
        func number(_ raw:Substring) throws -> Self {
            var value=String(raw).trimmingCharacters(in:.whitespacesAndNewlines)
            guard value.range(of:#"^[+-]?(?:[0-9]+(?:\.[0-9]{1,9})?|\.[0-9]{1,9})$"#,options:.regularExpression) != nil else {
                throw PolynomialError.invalid("Matrix entries and bounds must be numbers, not expressions or variables.")
            }
            let negative=value.hasPrefix("-")
            if value.hasPrefix("-") || value.hasPrefix("+") { value.removeFirst() }
            let magnitude=try Self.decimal(value)
            return negative ? try magnitude.negated():magnitude
        }
        let top=try number(parts[0]);let value=parts.count==2 ? try top.dividing(number(parts[1])):top
        return try sign.multiplying(value)
    }
}

nonisolated struct ExactMatrix:Equatable,Sendable {
    var cells:[[ExactRational]]
    var rows:Int { cells.count }
    var columns:Int { cells[0].count }
    init(_ cells:[[ExactRational]]) throws {
        guard (1...6).contains(cells.count),let width=cells.first?.count,(1...12).contains(width),cells.allSatisfy({$0.count==width}) else {
            throw PolynomialError.invalid("Use a rectangular matrix with 1–6 rows and 1–6 input columns.")
        }
        self.cells=cells
    }
    static func parse(_ input:String) throws -> Self {
        guard input.count<=5000 else { throw PolynomialError.invalid("Matrix input is too long.") }
        var text=input.trimmingCharacters(in:.whitespacesAndNewlines)
        text=text.replacingOccurrences(of:"\\left",with:"").replacingOccurrences(of:"\\right",with:"")
        if (text.hasPrefix("[") && text.hasSuffix("]")) || (text.hasPrefix("(") && text.hasSuffix(")")) {
            text=String(text.dropFirst().dropLast()).trimmingCharacters(in:.whitespacesAndNewlines)
        }
        var latex=false
        var declaredColumns:Int?
        for environment in ["bmatrix","pmatrix","matrix","array"] {
            let begin="\\begin{\(environment)}",end="\\end{\(environment)}"
            if text.hasPrefix(begin) {
                guard text.hasSuffix(end) else { throw PolynomialError.invalid("Close the matrix environment.") }
                text=String(text.dropFirst(begin.count).dropLast(end.count)).trimmingCharacters(in:.whitespacesAndNewlines)
                if environment == "array" {
                    guard text.hasPrefix("{"),let close=text.firstIndex(of:"}") else { throw PolynomialError.invalid("Specify array columns, such as {cc|c}.") }
                    let alignment=String(text[text.index(after:text.startIndex)..<close])
                    guard !alignment.isEmpty,alignment.allSatisfy({"clr| ".contains($0)}) else { throw PolynomialError.invalid("Only simple numeric matrix arrays are supported.") }
                    declaredColumns=alignment.filter {"clr".contains($0)}.count
                    text=String(text[text.index(after:close)...])
                }
                latex=true;break
            }
        }
        if !latex,text.hasPrefix("["),text.hasSuffix("]") { text=String(text.dropFirst().dropLast()) }
        if latex { text=text.replacingOccurrences(of:"\\\\",with:";") }
        else { text=text.replacingOccurrences(of:"\n",with:";") }
        let rawRows=text.split(separator:";",omittingEmptySubsequences:false)
        guard (1...6).contains(rawRows.count) else { throw PolynomialError.invalid("Use 1–6 matrix rows, separated by newlines or semicolons.") }
        var values:[[ExactRational]]=[]
        for row in rawRows {
            let raw=String(row).trimmingCharacters(in:.whitespacesAndNewlines)
            guard !raw.isEmpty else { throw PolynomialError.invalid("A matrix row is empty.") }
            let entries:[Substring]
            if raw.contains("&") { entries=raw.split(separator:"&",omittingEmptySubsequences:false) }
            else if raw.contains(",") { entries=raw.split(separator:",",omittingEmptySubsequences:false) }
            else { entries=raw.split(whereSeparator:{$0.isWhitespace}) }
            guard (1...6).contains(entries.count) else { throw PolynomialError.invalid("Use 1–6 input columns.") }
            values.append(try entries.map { try ExactRational.scalar(String($0)) })
        }
        let matrix=try Self(values)
        if let declaredColumns,declaredColumns != matrix.columns { throw PolynomialError.invalid("Array column declaration does not match its cells.") }
        return matrix
    }
    var latex:String { "\\begin{bmatrix}"+cells.map { $0.map(\.latex).joined(separator:" & ") }.joined(separator:" \\\\ ")+"\\end{bmatrix}" }
    var text:String { cells.map { $0.map(\.plain).joined(separator:", ") }.joined(separator:"; ") }
    static func identity(_ n:Int) throws -> Self { try Self((0..<n).map { r in (0..<n).map { r == $0 ? .one:.zero } }) }
    func transpose() throws -> Self { try Self((0..<columns).map { c in (0..<rows).map { cells[$0][c] } }) }
    func combining(_ other:Self,subtract:Bool) throws -> Self {
        guard rows==other.rows,columns==other.columns else { throw PolynomialError.invalid("Addition and subtraction require matrices of the same dimensions.") }
        return try Self((0..<rows).map { r in try (0..<columns).map { c in try cells[r][c].adding(subtract ? other.cells[r][c].negated():other.cells[r][c]) } })
    }
    func multiplying(_ other:Self) throws -> Self {
        guard columns==other.rows else { throw PolynomialError.invalid("For A × B, A's column count must equal B's row count.") }
        return try Self((0..<rows).map { r in try (0..<other.columns).map { c in
            var sum=ExactRational.zero
            for k in 0..<columns { try Task.checkCancellation();sum=try sum.adding(cells[r][k].multiplying(other.cells[k][c])) }
            return sum
        } })
    }
    func reduced(pivotLimit:Int?=nil) throws -> (matrix:Self,pivots:[Int],steps:[String]) {
        var a=cells,row=0,pivots:[Int]=[],steps:[String]=[]
        for col in 0..<(pivotLimit ?? columns) {
            try Task.checkCancellation()
            guard row<rows else { break }
            guard let next=(row..<rows).first(where:{a[$0][col].numerator != 0}) else { continue }
            if next != row { a.swapAt(next,row);steps.append("Swap R\(row+1) and R\(next+1).") }
            let pivot=a[row][col]
            if pivot != .one {
                for c in 0..<columns { a[row][c]=try a[row][c].dividing(pivot) }
                steps.append("R\(row+1) ← R\(row+1) / (\(pivot.plain)).")
            }
            for r in 0..<rows where r != row && a[r][col].numerator != 0 {
                let factor=a[r][col]
                for c in 0..<columns { a[r][c]=try a[r][c].adding(factor.multiplying(a[row][c]).negated()) }
                steps.append("R\(r+1) ← R\(r+1) − (\(factor.plain)) R\(row+1).")
            }
            pivots.append(col);row+=1
        }
        return (try Self(a),pivots,steps.isEmpty ? ["Already in reduced row echelon form."]:steps)
    }
    func determinant() throws -> ExactRational {
        guard rows==columns else { throw PolynomialError.invalid("A determinant requires a square matrix.") }
        var a=cells,result=ExactRational.one
        for col in 0..<columns {
            try Task.checkCancellation()
            guard let next=(col..<rows).first(where:{a[$0][col].numerator != 0}) else { return .zero }
            if next != col { a.swapAt(next,col);result=try result.negated() }
            let pivot=a[col][col];result=try result.multiplying(pivot)
            for r in (col+1)..<rows {
                let factor=try a[r][col].dividing(pivot)
                for c in col..<columns { a[r][c]=try a[r][c].adding(factor.multiplying(a[col][c]).negated()) }
            }
        }
        return result
    }
    func inverse() throws -> (matrix:Self,steps:[String]) {
        guard rows==columns else { throw PolynomialError.invalid("An inverse requires a square matrix.") }
        let identity=try Self.identity(rows)
        let augmented=try Self((0..<rows).map { cells[$0]+identity.cells[$0] })
        let reduction=try augmented.reduced(pivotLimit:columns)
        guard reduction.pivots.count==columns else { throw PolynomialError.invalid("This matrix is singular and has no inverse.") }
        let result=try Self(reduction.matrix.cells.map { Array($0.suffix(columns)) })
        guard try multiplying(result)==identity else { throw PolynomialError.invalid("The inverse verification failed.") }
        return (result,["Row-reduce [A | I] to [I | A⁻¹]."]+reduction.steps+["Verified A × A⁻¹ = I using exact arithmetic."])
    }
}

nonisolated struct MathComputationService {
    static let version="native-math-v6"
    func compute(_ original:MathComputationRequest) throws -> MathComputationAnswer {
        try Task.checkCancellation()
        let request=try PolynomialIntegralInput.resolved(original)
        if request.operation.isMatrix { return try matrix(request) }
        if request.operation.isAlgebra { return try AlgebraComputationService().compute(request) }
        guard [.integral,.definiteIntegral].contains(request.operation) || !PolynomialIntegralInput.hasIntegral(request.inputA) else {
            throw PolynomialError.invalid("Enter the polynomial itself for this operation, without an integral sign.")
        }
        let prepared=try PolynomialIntegralInput.hasIntegral(request.inputA) ? PolynomialIntegralInput.parse(request.inputA).prepared:PolynomialIntegrationService().prepare(request.inputA)
        guard request.variable.count==1,let char=request.variable.first,char.isASCII,char.isLetter,
              prepared.inferredVariable==nil || prepared.inferredVariable==request.variable else {
            throw PolynomialError.invalid("Choose the expression's single Latin-letter variable.")
        }
        let p=prepared.integrand,v=request.variable
        let output:String,steps:[String]
        switch request.operation {
        case .derivative:
            output=try p.derivative().latex(variable:v);steps=["Apply d(\(v)^n)/d\(v) = n\(v)^(n−1) term by term; constants become zero."]
        case .expand:
            output=p.latex(variable:v);steps=["Expand products and nonnegative integer powers, then collect like powers of \(v)."]
        case .evaluate:
            let x=try ExactRational.scalar(request.point)
            output=try evaluate(p,at:x).latex;steps=["Substitute \(v) = \(x.plain) and evaluate with exact fractions."]
        case .integral:
            let answer=try PolynomialIntegrationService().integrate(prepared,variable:v)
            output=answer.latex;steps=["Apply the polynomial power rule term by term.","Add an arbitrary integration constant.","Verified by exact differentiation."]
        case .definiteIntegral:
            let a=try PolynomialIntegralInput.numericBound(request.lower,label:"Lower"),b=try PolynomialIntegralInput.numericBound(request.upper,label:"Upper"),f=try p.antiderivative()
            let lower=try evaluate(f,at:a),upper=try evaluate(f,at:b)
            output=try upper.adding(lower.negated()).latex
            steps=["Integrate with respect to \(v), from \(a.plain) to \(b.plain).","Antiderivative F(\(v)) = "+f.latex(variable:v),"F(\(b.plain)) = \(upper.plain); F(\(a.plain)) = \(lower.plain).","Return F(upper) − F(lower); no arbitrary constant remains."]
        default:throw PolynomialError.invalid("Choose a polynomial operation.")
        }
        return MathComputationAnswer(request:request,inputLatex:request.inputA,outputLatex:output,steps:steps)
    }
    func evaluate(_ p:PolynomialValue,at x:ExactRational) throws -> ExactRational {
        var value=ExactRational.zero
        for degree in stride(from:p.degree,through:0,by:-1) { try Task.checkCancellation();value=try value.multiplying(x).adding(p.coefficients[degree] ?? .zero) }
        return value
    }
    private func matrix(_ request:MathComputationRequest) throws -> MathComputationAnswer {
        let a=try ExactMatrix.parse(request.inputA),output:String,steps:[String]
        switch request.operation {
        case .trace:
            guard a.rows==a.columns else {throw PolynomialError.invalid("Trace requires a square matrix.")}
            var sum=ExactRational.zero
            for i in 0..<a.rows {sum=try sum.adding(a.cells[i][i])}
            output=sum.latex;steps=["Add the diagonal entries using exact fractions."]
        case .matrixScale:
            let scalar=try ExactRational.scalar(request.point)
            output=try ExactMatrix(a.cells.map {try $0.map {try $0.multiplying(scalar)}}).latex
            steps=["Multiply every entry by "+scalar.plain+"."]
        case .matrixPower:
            let exponent=try ExactRational.scalar(request.point)
            guard a.rows==a.columns,exponent.denominator==1,(-10...10).contains(exponent.numerator) else {throw PolynomialError.invalid("Use a square matrix and an integer exponent from −10 to 10.")}
            let base=exponent.numerator<0 ? try a.inverse().matrix:a
            var power=try ExactMatrix.identity(a.rows)
            for _ in 0..<Int(abs(exponent.numerator)) {try Task.checkCancellation();power=try power.multiplying(base)}
            output=power.latex;steps=["Exponent zero returns the identity; negative powers use the verified inverse.","Multiply exactly to obtain exponent "+exponent.plain+"."]
        case .nullspace,.columnSpace,.rowSpace:
            let r=try a.reduced();var notes=r.steps
            if request.operation == .columnSpace {
                output=r.pivots.isEmpty ? "\\varnothing":try ExactMatrix(a.cells.map {row in r.pivots.map {row[$0]}}).latex
                notes.append(r.pivots.isEmpty ? "The column space is {0}; its basis is empty.":"Columns of this output are the original matrix's pivot columns and form a column-space basis.")
            } else if request.operation == .rowSpace {
                output=r.pivots.isEmpty ? "\\varnothing":try ExactMatrix(Array(r.matrix.cells.prefix(r.pivots.count))).latex
                notes.append(r.pivots.isEmpty ? "The row space is {0}; its basis is empty.":"Rows of this output are the nonzero RREF rows and form a row-space basis.")
            } else {
                let free=(0..<a.columns).filter {!r.pivots.contains($0)}
                if free.isEmpty {output="\\varnothing";notes.append("The nullspace contains only the zero vector; its basis is empty.")}
                else {
                    let vectors=try ExactMatrix((0..<a.columns).map {col in try free.map {f in
                        if let row=r.pivots.firstIndex(of:col) {return try r.matrix.cells[row][f].negated()}
                        return col==f ? ExactRational.one:ExactRational.zero
                    }})
                    let checked=try a.multiplying(vectors)
                    guard checked.cells.flatMap({$0}).allSatisfy({$0.numerator==0}) else {throw PolynomialError.invalid("Nullspace verification failed.")}
                    output=vectors.latex;notes.append("Columns are nullspace basis vectors. Verified A times every basis vector equals zero.")
                }
            }
            steps=notes
        case .rref:let r=try a.reduced();output=r.matrix.latex;steps=r.steps
        case .rank:let r=try a.reduced();output=String(r.pivots.count);steps=r.steps+["Rank is the number of pivot columns: \(r.pivots.count)."]
        case .determinant:output=try a.determinant().latex;steps=["Use exact Gaussian elimination; each row swap changes the determinant's sign.","Multiply the pivots of the triangular matrix; a missing pivot gives determinant zero."]
        case .inverse:let r=try a.inverse();output=r.matrix.latex;steps=r.steps
        case .transpose:output=try a.transpose().latex;steps=["Exchange rows and columns."]
        case .matrixAdd,.matrixSubtract:
            output=try a.combining(ExactMatrix.parse(request.inputB),subtract:request.operation == .matrixSubtract).latex;steps=["Combine corresponding entries with exact arithmetic."]
        case .matrixMultiply:
            output=try a.multiplying(ExactMatrix.parse(request.inputB)).latex;steps=["Each output entry is the dot product of a row of A and a column of B."]
        case .solve:
            guard a.columns>=2 else { throw PolynomialError.invalid("Enter [A | b]: at least one coefficient column and a final right-hand-side column.") }
            let n=a.columns-1,r=try a.reduced(pivotLimit:n)
            if r.matrix.cells.contains(where:{$0.prefix(n).allSatisfy({$0.numerator==0}) && $0[n].numerator != 0}) {
                output="\\text{No solution}";steps=r.steps+["A zero coefficient row has a nonzero right-hand side; the system is inconsistent."]
            } else {
                let free=(0..<n).filter { !r.pivots.contains($0) }
                var equations:[String]=[]
                for col in 0..<n {
                    let rhs:String
                    if let index=free.firstIndex(of:col) { rhs="t_{\(index+1)}" }
                    else {
                        let row=r.pivots.firstIndex(of:col)!
                        var expression=r.matrix.cells[row][n].latex
                        for (i,f) in free.enumerated() where r.matrix.cells[row][f].numerator != 0 {
                            expression += " + \\left("+(try r.matrix.cells[row][f].negated()).latex+"\\right)t_{\(i+1)}"
                        }
                        rhs=expression
                    }
                    equations.append("x_{\(col+1)} &= "+rhs)
                }
                output="\\begin{aligned}"+equations.joined(separator:" \\\\ ")+"\\end{aligned}"
                steps=r.steps+[free.isEmpty ? "Unique solution.":"Infinitely many solutions; t₁…t\(free.count) are arbitrary real parameters."]
            }
        default:throw PolynomialError.invalid("Choose a matrix operation.")
        }
        return MathComputationAnswer(request:request,inputLatex:a.latex,outputLatex:output,steps:steps)
    }
}

actor MathComputationWorker {
    static let shared=MathComputationWorker()
    func compute(_ original:MathComputationRequest) async throws -> MathComputationAnswer {
        let request=original.operation.isMatrix ? original:try WorksheetMathNotation.resolved(original)
        let answer=try await execute(request)
        return MathComputationAnswer(request:answer.request,inputLatex:original.inputA,outputLatex:answer.outputLatex,steps:answer.steps,engineVersion:answer.engineVersion)
    }
    /// Execute the normalized request in the native service or isolated calculus worker.
    private func execute(_ request:MathComputationRequest) async throws -> MathComputationAnswer {
#if canImport(UIKit)
        if !request.operation.isComplex,["e","i"].contains(request.variable.trimmingCharacters(in:.whitespacesAndNewlines)),!(await Calc1MathService.supports(request.operation)) {
            throw PolynomialError.invalid("e and i are reserved constants in this calculator. Use x or t for a polynomial variable.")
        }
        // Euler's constant / scientific notation must not be interpreted as
        // a polynomial variable by the legacy single-letter parser.
        if request.inputA.contains("e") || request.inputA.contains("E") {
            if await Calc1MathService.supports(request.operation) { return try await Calc1MathService.compute(request) }
        }
#endif
        do { return try MathComputationService().compute(request) }
        catch {
#if canImport(UIKit)
            if await Calc1MathService.supports(request.operation) { return try await Calc1MathService.compute(request) }
#endif
            throw error
        }
    }
}
