import XCTest

final class DefiniteIntegralUITests:XCTestCase {
    override func setUpWithError() throws { continueAfterFailure=false }
    @MainActor private func open()->XCUIApplication {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication();app.launchArguments=["--polynomial-ui-test","--definite-integral-ui","--canvas-ui-store",UUID().uuidString];app.launch()
        let chip=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","expressionIndicator-")).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout:15));chip.tap()
        let action=app.buttons["suggestedComputation"];XCTAssertTrue(action.waitForExistence(timeout:8))
        XCTAssertEqual(action.label,"Evaluate definite integral");XCTAssertFalse(app.buttons["integrateExpression"].exists);action.tap()
        XCTAssertTrue(app.collectionViews["mathWorkbenchForm"].waitForExistence(timeout:8));return app
    }
    @MainActor private func reveal(_ element:XCUIElement,_ app:XCUIApplication) {
        for _ in 0..<8 { if element.exists && element.isHittable { return };app.collectionViews["mathWorkbenchForm"].swipeUp() }
        if !element.isHittable {print(app.debugDescription)};XCTAssertTrue(element.isHittable)
    }
    @MainActor func testRecognizedBoundsAndVariableComputeWithoutRetyping() {
        let app=open(),form=app.collectionViews["mathWorkbenchForm"]
        let read=app.descendants(matching:.any).matching(identifier:"integralReadVariable").firstMatch;reveal(read,app)
        XCTAssertFalse(app.textFields["mathVariable"].exists)
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"integralReadLower").firstMatch.exists)
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"integralReadUpper").firstMatch.exists)
        waitForMathCompute(app);app.buttons["computeMathToolbar"].tap()
        let output=form.staticTexts["integralOutput"].firstMatch;reveal(output,app);XCTAssertEqual(output.label,"3")
        let insert=form.buttons["insertIntegralResult"].firstMatch;reveal(insert,app);insert.tap()
        XCTAssertTrue(app.descendants(matching:.any).matching(identifier:"insertedCanvasResult").firstMatch.waitForExistence(timeout:15))
    }
    @MainActor func testSeparatePartsStartWithRecognizedVariableAndLimits() {
        let app=open();let edit=app.buttons["Edit this calculation’s input"];reveal(edit,app);edit.tap()
        let parts=app.buttons["editIntegralParts"];reveal(parts,app);parts.tap();waitForMathCompute(app)
        let lower=app.textFields["mathLower"],upper=app.textFields["mathUpper"]
        reveal(lower,app);XCTAssertEqual(lower.value as? String,"-1")
        reveal(upper,app);XCTAssertEqual(upper.value as? String,"2")
        let variable=app.descendants(matching:.any).matching(identifier:"integralReadVariable").firstMatch
        for _ in 0..<5 {if variable.exists{break};app.collectionViews["mathWorkbenchForm"].swipeDown()}
        XCTAssertTrue(variable.label.contains("t"))
        waitForMathCompute(app);app.buttons["computeMathToolbar"].tap()
        let output=app.collectionViews["mathWorkbenchForm"].staticTexts["integralOutput"].firstMatch;reveal(output,app);XCTAssertEqual(output.label,"3")
    }
}
