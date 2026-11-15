import XCTest

final class ComputationUITests:XCTestCase {
    override func setUpWithError() throws { continueAfterFailure=false }
    @MainActor
    private func app()->XCUIApplication {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication();app.launchArguments=["--polynomial-ui-test","--canvas-ui-store",UUID().uuidString,"--canvas-empty-ui"]
        app.launch();XCTAssertTrue(app.buttons["openMathWorkbench"].waitForExistence(timeout:15));return app
    }
    @MainActor
    private func operation(_ title:String,in app:XCUIApplication) {
        let calculus=["Differentiate","Expand","Evaluate","Antiderivative","Definite integral"]
        chooseMath(title,category:calculus.contains(title) ? "Calc 1":"Matrices",in:app)
    }
    @MainActor
    private func reveal(_ element:XCUIElement,in app:XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable {return}
            let form=app.descendants(matching:.any).matching(identifier:"mathWorkbenchForm").firstMatch
            if form.exists { form.swipeUp() } else { app.scrollViews.firstMatch.swipeUp() }
        }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor
    func testMatrixComputeInsertMoveUndoAndReopen() {
        let app=app();app.buttons["openMathWorkbench"].tap();reviewMathInputs(app)
        XCTAssertTrue(app.textFields["matrixA-0-0"].waitForExistence(timeout:5))
        waitForMathCompute(app);app.buttons["computeMathToolbar"].tap()
        let output=app.collectionViews["mathWorkbenchForm"].staticTexts["integralOutput"].firstMatch
        reveal(output,in:app)
        XCTAssertTrue(output.label.contains("bmatrix"))
        let insert=app.buttons["insertIntegralResult"].firstMatch
        reveal(insert,in:app);insert.tap()
        let tile=app.descendants(matching:.any).matching(identifier:"insertedCanvasResult").firstMatch
        let inserted=tile.waitForExistence(timeout:15)
        if !inserted { print(app.debugDescription) }
        XCTAssertTrue(inserted)
        // Finger dragging a result works directly while Pen remains selected.
        let before=tile.frame,point=tile.coordinate(withNormalizedOffset:CGVector(dx:0.25,dy:0.1))
        point.press(forDuration:0.1,thenDragTo:point.withOffset(CGVector(dx:100,dy:60)))
        XCTAssertGreaterThan(tile.frame.minX,before.minX+60)
        app.buttons["undoCanvas"].tap();XCTAssertEqual(tile.frame.minX,before.minX,accuracy:4)
        app.buttons["redoCanvas"].tap()
        app.buttons["tool-eraser"].tap();if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        let eraserStart=tile.coordinate(withNormalizedOffset:CGVector(dx:0.25,dy:0.1))
        let penMoved=tile.frame
        eraserStart.press(forDuration:0.1,thenDragTo:eraserStart.withOffset(CGVector(dx:60,dy:40)))
        XCTAssertGreaterThan(tile.frame.minX,penMoved.minX+40)
        app.buttons["tool-pen"].tap();if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        let canvas=app.scrollViews["notebookInkCanvas"],priorInk=canvas.value as? String
        let ink=canvas.coordinate(withNormalizedOffset:CGVector(dx:0.8,dy:0.75))
        ink.press(forDuration:0.05,thenDragTo:ink.withOffset(CGVector(dx:60,dy:30)))
        XCTAssertNotEqual(canvas.value as? String,priorInk,"Direct card dragging must not block writing outside cards")
        let moved=tile.frame
        app.terminate();app.launch();XCTAssertTrue(tile.waitForExistence(timeout:15))
        XCTAssertEqual(tile.frame.minX,moved.minX,accuracy:4)
        app.buttons["openMathWorkbench"].tap()
        XCTAssertTrue(app.buttons["reviewMathInputs"].waitForExistence(timeout:5))
        XCTAssertFalse(app.staticTexts["integralOutput"].exists,"A new free-form calculation must not carry over a previous result")

    }
    @MainActor
    func testPolynomialAndRecoverableMatrixError() {
        let app=app();app.buttons["openMathWorkbench"].tap()
        operation("Differentiate",in:app)
        XCTAssertTrue(app.textFields["mathPolynomial"].waitForExistence(timeout:5))
        waitForMathCompute(app);app.buttons["computeMathToolbar"].tap()
        let output=app.collectionViews["mathWorkbenchForm"].staticTexts["integralOutput"].firstMatch;reveal(output,in:app)
        XCTAssertEqual(output.label,"2x + 3")
        if app.buttons["Done"].exists { app.buttons["Done"].tap() };app.buttons["openMathWorkbench"].tap()
        operation("Inverse",in:app)
        app.segmentedControls["matrixAInputMode"].buttons["LaTeX / rows"].tap()
        let field=app.descendants(matching:.any).matching(identifier:"matrixAText").firstMatch
        XCTAssertTrue(field.waitForExistence(timeout:5));app.buttons["matrixAClear"].tap();field.tap()
        field.typeText("1,2;2,4")
        waitForMathCompute(app);app.buttons["computeMathToolbar"].tap()
        let error=app.staticTexts["mathError"];reveal(error,in:app)
        XCTAssertTrue(error.label.contains("singular"),error.label)
    }
    @MainActor
    func testReviewedSourceOpensMoreComputations() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication();app.launchArguments=["--polynomial-ui-test","--canvas-ui-store",UUID().uuidString]
        app.launch();XCTAssertTrue(app.buttons["recognizeNotebook"].waitForExistence(timeout:15));app.buttons["recognizeNotebook"].tap()
        let more=app.buttons["moreComputations"].firstMatch
        XCTAssertTrue(more.waitForExistence(timeout:10));more.tap()
        operation("Differentiate",in:app)
        // The fixture is a full integral: derivative must reject it rather than
        // silently differentiate its integrand. The source can still be integrated.
        reveal(app.buttons["computeMath"],in:app);waitForMathCompute(app);app.buttons["computeMathToolbar"].tap()
        XCTAssertTrue(app.staticTexts["mathError"].waitForExistence(timeout:5))
        operation("Antiderivative",in:app);reveal(app.buttons["computeMath"],in:app);waitForMathCompute(app);app.buttons["computeMathToolbar"].tap()
        let output=app.collectionViews["mathWorkbenchForm"].staticTexts["integralOutput"].firstMatch;reveal(output,in:app)
        XCTAssertTrue(output.label.contains("C"))
    }
}
