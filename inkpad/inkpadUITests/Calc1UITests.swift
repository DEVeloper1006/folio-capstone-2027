import XCTest

final class Calc1UITests:XCTestCase {
    override func setUpWithError() throws {continueAfterFailure=false}
    @MainActor private func app(_ extra:[String])->XCUIApplication {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication();app.launchArguments=["--polynomial-ui-test","--canvas-ui-store",UUID().uuidString]+extra
        app.launch();XCTAssertTrue(app.buttons["openMathWorkbench"].waitForExistence(timeout:15));return app
    }
    @MainActor func testRowContextAndMenuDoNotCarryOtherRowsResults() {
        let app=app(["--two-row-calc1"])
        let chips=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","expressionIndicator-"))
        XCTAssertTrue(chips.element(boundBy:1).waitForExistence(timeout:8));chips.element(boundBy:0).tap()
        XCTAssertFalse(app.textViews.matching(NSPredicate(format:"identifier BEGINSWITH %@","latexEditor-")).firstMatch.exists,"Preview should not expose raw editing by default")
        app.buttons["suggestedComputation"].tap();waitForMathCompute(app)
        XCTAssertEqual(app.staticTexts["mathTargetLatex"].label,#"\sin x"#)
        XCTAssertFalse(app.textFields["mathLower"].exists);XCTAssertFalse(app.textFields["mathPoint"].exists)
        let preview=XCTAttachment(screenshot:app.screenshot());preview.name="Calc 1 row review";preview.lifetime = .keepAlways;add(preview)
        app.buttons["computeMathToolbar"].tap()
        let form=app.collectionViews["mathWorkbenchForm"],output=form.staticTexts["integralOutput"].firstMatch
        revealMath(output,app);XCTAssertTrue(output.label.contains("cos"))
        app.buttons["closeMathWorkbench"].tap();app.buttons["closeExpressionInspector"].tap()
        chips.element(boundBy:1).tap();app.buttons["moreComputations"].tap()
        XCTAssertTrue(app.buttons["reviewMathInputs"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["mathTargetLatex"].label,"x^2")
        XCTAssertFalse(app.staticTexts["integralOutput"].exists);XCTAssertFalse(app.buttons["Earlier results for this row"].exists)
        XCTAssertFalse(app.textFields["mathPolynomial"].exists,"Choosing an operation should not display unrelated input fields")
        reviewMathInputs(app);app.buttons["computeMathToolbar"].tap()
        revealMath(output,app);XCTAssertEqual(output.label,"x^{2}")
        let result=XCTAttachment(screenshot:app.screenshot());result.name="Isolated row result";result.lifetime = .keepAlways;add(result)
    }
    @MainActor func testNarrowIPadToolbarKeepsDrawingAndComputeSeparate() {
        let app=app(["--canvas-empty-ui","--narrow-window-ui"])
        let more=app.buttons["notebookMoreActions"]
        XCTAssertTrue(more.waitForExistence(timeout:8));XCTAssertTrue(app.buttons["tool-pen"].isHittable)
        XCTAssertTrue(app.buttons["tool-eraser"].isHittable);XCTAssertTrue(app.buttons["openMathWorkbench"].isHittable)
        XCTAssertFalse(app.buttons["tool-eraser"].frame.intersects(app.buttons["openMathWorkbench"].frame))
        XCTAssertFalse(app.buttons["redoCanvas"].frame.intersects(app.buttons["recognizeNotebook"].frame))
        more.tap();XCTAssertTrue(app.buttons["Recognition settings"].waitForExistence(timeout:5))
    }
    @MainActor func testNumericalIntegralReviewOnlyShowsNeededParameters() {
        let app=app(["--canvas-empty-ui"]);app.buttons["openMathWorkbench"].tap()
        XCTAssertFalse(app.textFields["matrixA-0-0"].exists)
        chooseMath("Numerical definite integral",category:"Calc 1",in:app)
        let field=app.descendants(matching:.any).matching(identifier:"mathPolynomial").firstMatch
        revealMath(app.buttons["clearMathExpression"],app);app.buttons["clearMathExpression"].tap();field.tap();field.typeText(#"\int_0^1 e^{-x^2} dx"#)
        waitForMathCompute(app)
        XCTAssertFalse(app.textFields["mathPoint"].exists);XCTAssertFalse(app.textFields["mathUpper"].exists,"Full integral should supply its limits")
        app.buttons["computeMathToolbar"].tap()
        let output=app.collectionViews["mathWorkbenchForm"].staticTexts["integralOutput"].firstMatch;revealMath(output,app)
        XCTAssertTrue(output.label.contains(#"\approx"#));XCTAssertTrue(output.label.contains("0.746824"))
    }
}
