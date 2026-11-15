import XCTest
@testable import inkpad

final class AlgebraComputationTests:XCTestCase {
    private func compute(_ op:MathOperation,_ a:String,_ b:String="",point:String="2") throws -> MathComputationAnswer {
        try MathComputationService().compute(MathComputationRequest(operation:op,inputA:a,inputB:b,point:point))
    }
    func testArithmeticAndPolynomialAlgebra() throws {
        XCTAssertEqual(try compute(.arithmetic,"(3/4+2)/5").outputLatex,#"\frac{11}{20}"#)
        XCTAssertThrowsError(try compute(.arithmetic,"x-x"))
        XCTAssertEqual(try compute(.simplify,"2x+3x-4+1").outputLatex,"5x - 3")
        XCTAssertEqual(try compute(.polynomialAdd,"x^2+1","2x^2-1").outputLatex,"3x^{2}")
        XCTAssertEqual(try compute(.polynomialSubtract,"x^2+1","x^2+1").outputLatex,"0")
        XCTAssertEqual(try compute(.polynomialMultiply,"x+1","x-1").outputLatex,"x^{2} - 1")
        XCTAssertEqual(try compute(.equivalent,"(x+1)^2","x^2+2x+1").outputLatex,#"\text{Equivalent}"#)
        XCTAssertEqual(try compute(.equivalent,"x^2","x").outputLatex,#"\text{Not equivalent}"#)
        XCTAssertThrowsError(try compute(.equivalent,"x","t"))
    }
    func testPolynomialDivisionAndVerification() throws {
        let parser=PolynomialIntegrationService()
        for (a,b) in [("x^3-1","x-1"),("x^2+1","x+1"),("2x^4-3x+1","x^2+1"),("1","x+1"),("0","x+1")] {
            let original=try parser.prepare(a).integrand,divisor=try parser.prepare(b).integrand
            let result=try original.division(by:divisor)
            XCTAssertEqual(try result.quotient.multiplying(divisor).adding(result.remainder),original)
            XCTAssertTrue(result.remainder.coefficients.isEmpty || result.remainder.degree<divisor.degree)
        }
        XCTAssertEqual(try compute(.polynomialDivide,"x^2-1","x-1").outputLatex,"x + 1")
        XCTAssertTrue(try compute(.polynomialDivide,"x^2+1","x+1").outputLatex.contains("\\frac{2}{x + 1}"))
        XCTAssertThrowsError(try compute(.polynomialDivide,"x","0"))
    }
    func testLinearQuadraticAndDegenerateEquations() throws {
        XCTAssertEqual(try compute(.solveEquation,"2x+3=11").outputLatex,"x = 4")
        XCTAssertTrue(try compute(.solveEquation,"x^2-5x+6=0").outputLatex.contains("3, 2"))
        XCTAssertEqual(try compute(.solveEquation,"(x-2)^2=0").outputLatex,"x = 2")
        XCTAssertTrue(try compute(.solveEquation,"x^2=2").outputLatex.contains("\\sqrt{8}"))
        XCTAssertEqual(try compute(.solveEquation,"x^2+1=0").outputLatex,#"x = \pm i"#)
        XCTAssertEqual(try compute(.solveEquation,"x=x").outputLatex,#"x \in \mathbb{C}"#)
        XCTAssertEqual(try compute(.solveEquation,"1=2").outputLatex,#"\varnothing"#)
        XCTAssertThrowsError(try compute(.solveEquation,"x^3=1"))
        XCTAssertThrowsError(try compute(.solveEquation,"x=1=2"))
        XCTAssertThrowsError(try compute(.solveEquation,#"\sin{x}=0"#))
        XCTAssertEqual(try AlgebraComputationService().rationalSquareRoot(ExactRational(9,16)),try ExactRational(3,4))
    }
    func testComplexQuadraticRootsStayExactAndVerified() throws {
        let cases:[(String,String)]=[
            ("x^2+2x+5=0",#"x = -1 \pm 2\,i"#),
            ("x^2+2=0",#"x = \pm i\sqrt{2}"#),
            ("-x^2-1=0",#"x = \pm i"#),
            ("4x^2+1=0",#"x = \pm \frac{1}{2}\,i"#),
            ("x^2+12=0",#"x = \pm 2\,i\sqrt{3}"#),
            ("x^2/2+x+5/2=0",#"x = -1 \pm 2\,i"#)]
        for (input,expected) in cases {
            let answer=try compute(.solveEquation,input)
            XCTAssertEqual(answer.outputLatex,expected,input)
            XCTAssertTrue(answer.steps.contains{$0.contains("verified")},input)
            XCTAssertEqual(answer.engineVersion,"native-math-v6")
        }
        XCTAssertThrowsError(try compute(.solveEquation,"999999999999x^2+999999999999=0"))
    }
    func testExactPolynomialInequalitiesAndDegenerateCases() throws {
        let samples:[(String,String)]=[
            ("x^2-1<=0",#"x \in \left[-1, 1\right]"#),
            ("x^2-1>0",#"x \in \left(-\infty, -1\right) \cup \left(1, \infty\right)"#),
            ("-2x+3>7",#"x \in \left(-\infty, -2\right)"#),
            ("x^2+1>0",#"x \in \mathbb{R}"#),
            ("x^2+1<=0",#"\varnothing"#),
            ("(x-2)^2<=0","x = 2"),("(x-2)^2>=0",#"x \in \mathbb{R}"#),
            ("0<0",#"\varnothing"#),("0<=0",#"x \in \mathbb{R}"#),
            ("x^2-2≤0",#"x \in \left[-\sqrt{2}, \sqrt{2}\right]"#)]
        for (input,expected) in samples {XCTAssertEqual(try compute(.solveInequality,input).outputLatex,expected,input)}
        let t=try compute(.solveInequality,"2t>=4");XCTAssertEqual(t.request.variable,"t");XCTAssertTrue(t.outputLatex.hasPrefix("t"))
        for input in ["0<x<1","1/x>0","x^3>0","x+y>1","x=1","1E-3<=0"] {XCTAssertThrowsError(try compute(.solveInequality,input),input)}
    }
    func testAbsoluteLinearEquationsAndComposition() throws {
        XCTAssertEqual(try compute(.solveAbsolute,"|2x-3|=5").outputLatex,#"x \in \left\{4, -1\right\}"#)
        XCTAssertEqual(try compute(.solveAbsolute,"abs(2x-3)=0").outputLatex,#"x = \frac{3}{2}"#)
        XCTAssertEqual(try compute(.solveAbsolute,"|x|=-1").outputLatex,#"\varnothing"#)
        XCTAssertEqual(try compute(.solveAbsolute,"|-2|=2").outputLatex,#"x \in \mathbb{R}"#)
        XCTAssertThrowsError(try compute(.solveAbsolute,"|x^2|=4"));XCTAssertThrowsError(try compute(.solveAbsolute,"|x|+1=2"))
        XCTAssertEqual(try compute(.compose,"x^2+1","x+2").outputLatex,"x^{2} + 4x + 5")
        XCTAssertEqual(try compute(.compose,"x+2","x^2+1").outputLatex,"x^{2} + 3")
        XCTAssertEqual(try compute(.compose,"x^3+2x+3","0").outputLatex,"3")
        XCTAssertEqual(try compute(.compose,"0","x^2").outputLatex,"0")
        XCTAssertEqual(try compute(.compose,"t^2","2t").request.variable,"t")
        XCTAssertThrowsError(try compute(.compose,"x^20","x^2"));XCTAssertThrowsError(try compute(.compose,"x","t"))
    }
    func testExactComplexArithmeticAndBounds() throws {
        let samples:[(String,String)]=[("(1+i)/(1-i)","i"),("(1+i)^2",#"2\,i"#),("(1+i)(1-i)","2"),("i^4","1"),("1/2+3i/4",#"\frac{1}{2} + \frac{3}{4}\,i"#)]
        for (input,expected) in samples {XCTAssertEqual(try compute(.complexCalculate,input).outputLatex,expected)}
        XCTAssertEqual(try compute(.complexConjugate,"3+4i").outputLatex,#"3 - 4\,i"#)
        XCTAssertEqual(try compute(.complexModulus,"3+4i").outputLatex,"5")
        XCTAssertEqual(try compute(.complexModulus,"1+i").outputLatex,#"\sqrt{2}"#)
        XCTAssertEqual(try MathComputationService().compute(.init(operation:.complexCalculate,inputA:"i",inputB:"1E-3",point:"unused",lower:"unused",upper:"unused")).outputLatex,"i")
        for input in ["1/(i-i)","0^0","i^21","x+i","sin(i)","__import__('os')"] {XCTAssertThrowsError(try compute(.complexCalculate,input),input)}
    }
    func testFactoringReconstructsAndReportsRemainingFactors() throws {
        let parser=PolynomialIntegrationService()
        for input in ["x^2-9","x^2+2x+1","2x^3-2x","x^4","x^2+1","(2x-1)(3x+2)","0","5"] {
            let result=try compute(.factor,input)
            XCTAssertEqual(try parser.prepare(result.outputLatex).integrand,try parser.prepare(input).integrand,input)
        }
        XCTAssertTrue(try compute(.factor,"x^2-9").outputLatex.contains("x - 3"))
        XCTAssertTrue(try compute(.factor,"x^4+3x^2+2").steps.contains {$0.contains("remaining") || $0.contains("Remaining")})
        XCTAssertThrowsError(try compute(.factor,"x^2+100000001"))
    }
    func testMatrixAdditionalOperationsAndSpaces() throws {
        XCTAssertEqual(try compute(.trace,"1,2;3,4").outputLatex,"5")
        XCTAssertThrowsError(try compute(.trace,"1,2,3"))
        XCTAssertEqual(try compute(.matrixScale,"1,2;3,4",point:"1/2").outputLatex,try ExactMatrix.parse("1/2,1;3/2,2").latex)
        XCTAssertEqual(try compute(.matrixPower,"1,2;0,1",point:"-2").outputLatex,try ExactMatrix.parse("1,-4;0,1").latex)
        XCTAssertEqual(try compute(.matrixPower,"0,0;0,0",point:"0").outputLatex,try ExactMatrix.identity(2).latex)
        XCTAssertThrowsError(try compute(.matrixPower,"1,2;2,4",point:"-1"))
        XCTAssertThrowsError(try compute(.matrixPower,"1,2;3,4",point:"11"))
        XCTAssertThrowsError(try compute(.matrixPower,"1,2;3,4",point:"1/2"))
        let a=try ExactMatrix.parse("1,2,3;2,4,6")
        let null=try ExactMatrix.parse(compute(.nullspace,a.text).outputLatex)
        XCTAssertEqual(null.columns,2)
        XCTAssertTrue(try a.multiplying(null).cells.flatMap {$0}.allSatisfy {$0.numerator==0})
        XCTAssertEqual(try compute(.columnSpace,a.text).outputLatex,try ExactMatrix.parse("1;2").latex)
        XCTAssertEqual(try compute(.rowSpace,a.text).outputLatex,try ExactMatrix.parse("1,2,3").latex)
        XCTAssertEqual(try compute(.nullspace,"1,0;0,1").outputLatex,#"\varnothing"#)
    }
}
