import XCTest

final class AlgebraUITests:XCTestCase {
    override func setUpWithError() throws {continueAfterFailure=false}
    @MainActor
    func testAlgebraCategoryEquationAndBinaryInput() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication();app.launchArguments=["--polynomial-ui-test","--canvas-ui-store",UUID().uuidString,"--canvas-empty-ui"]
        app.launch();XCTAssertTrue(app.buttons["openMathWorkbench"].waitForExistence(timeout:15));app.buttons["openMathWorkbench"].tap()
        let category=app.segmentedControls["mathCategory"]
        XCTAssertTrue(category.waitForExistence(timeout:5));category.buttons["Algebra"].tap()
        app.buttons["mathOperation"].tap();app.buttons["Solve linear / quadratic equation"].tap();reviewMathInputs(app)
        let input=app.descendants(matching:.any).matching(identifier:"mathPolynomial").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout:5));app.buttons["clearMathExpression"].tap();input.tap();input.typeText("2x+3=11")
        XCTAssertEqual(input.value as? String,"2x+3=11")
        let form=app.collectionViews["mathWorkbenchForm"]
        let compute=app.buttons["computeMathToolbar"]
        for _ in 0..<6 {if compute.exists && compute.isHittable{break};form.swipeUp()}
        waitForMathCompute(app);compute.tap()
        let output=form.staticTexts["integralOutput"].firstMatch
        for _ in 0..<6 {if output.exists && output.isHittable{break};form.swipeUp()}
        if !output.exists {print(app.debugDescription)}
        XCTAssertTrue(output.exists)
        XCTAssertEqual(output.label,"x = 4")
        chooseMath("Add polynomials",category:"Algebra",in:app)
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"mathExpressionB").firstMatch.waitForExistence(timeout:5))
    }
    @MainActor func testNewExactAlgebraCommandsReviewComputeAndKeepFieldsScoped() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication();app.launchArguments=["--polynomial-ui-test","--canvas-ui-store",UUID().uuidString,"--canvas-empty-ui"]
        app.launch();XCTAssertTrue(app.buttons["openMathWorkbench"].waitForExistence(timeout:15));app.buttons["openMathWorkbench"].tap()
        let samples:[(String,String,String,String)]=[
            ("Solve polynomial inequality","x^2-1<=0","",#"x \in \left[-1, 1\right]"#),
            ("Solve absolute-value equation","|2x-3|=5","",#"x \in \left\{4, -1\right\}"#),
            ("Compose A(B(x))","x^2+1","x+2","x^{2} + 4x + 5"),
            ("Calculate complex expression","(1+i)/(1-i)","","i"),
            ("Complex conjugate","3+4i","",#"3 - 4\,i"#),
            ("Complex modulus","3+4i","","5")]
        for (index,sample) in samples.enumerated() {
            if index>0 {revealMath(app.buttons["anotherRowComputation"],app)}
            chooseMath(sample.0,category:"Algebra",in:app)
            let input=app.descendants(matching:.any).matching(identifier:"mathPolynomial").firstMatch
            revealMath(app.buttons["clearMathExpression"],app);app.buttons["clearMathExpression"].tap();input.tap();input.typeText(sample.1)
            if app.buttons["dismissMathKeyboard"].exists {app.buttons["dismissMathKeyboard"].tap()}
            if !sample.2.isEmpty {let b=app.descendants(matching:.any).matching(identifier:"mathExpressionB").firstMatch;revealMath(b,app);b.tap();b.typeText(sample.2);if app.buttons["dismissMathKeyboard"].exists {app.buttons["dismissMathKeyboard"].tap()}}
            else {XCTAssertFalse(app.descendants(matching:.any).matching(identifier:"mathExpressionB").firstMatch.exists)}
            XCTAssertFalse(app.textFields["mathLower"].exists);XCTAssertFalse(app.textFields["mathPoint"].exists)
            waitForMathCompute(app);app.buttons["computeMathToolbar"].tap()
            let output=app.collectionViews["mathWorkbenchForm"].staticTexts["integralOutput"].firstMatch;revealMath(output,app)
            XCTAssertEqual(output.label,sample.3,sample.0)
            if index<2 {XCTAssertFalse(app.buttons["Use this result as input"].exists)}
        }
    }

}
