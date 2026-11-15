import XCTest

final class PolynomialUITests:XCTestCase {
    override func setUpWithError() throws {continueAfterFailure=false}
    @MainActor func testComputeRemoveAndUnsavedRecognitionEditGuard() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication();app.launchArguments=["--polynomial-ui-test","--canvas-ui-store",UUID().uuidString];app.launch()
        XCTAssertTrue(app.buttons["recognizeNotebook"].waitForExistence(timeout:20));app.buttons["recognizeNotebook"].tap()
        let action=app.buttons["suggestedComputation"].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout:10));action.tap();waitForMathCompute(app);app.buttons["computeMathToolbar"].tap()
        let form=app.collectionViews["mathWorkbenchForm"],output=form.staticTexts["integralOutput"].firstMatch
        revealMath(output,app);XCTAssertEqual(output.label,#"\frac{t^{3}}{3} + \frac{3t^{2}}{2} + 2t + C"#)
        let remove=form.buttons["removeIntegralResult"].firstMatch;revealMath(remove,app);remove.tap()
        XCTAssertFalse(output.exists);app.buttons["Done"].tap()
        let edit=app.buttons["Edit recognition"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout:5));edit.tap()
        let editor=app.textViews.matching(NSPredicate(format:"identifier BEGINSWITH %@","latexEditor-")).firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout:5));editor.tap();editor.typeText("t")
        XCTAssertFalse(app.buttons["moreComputations"].exists,"Unaccepted edits must not reach computation")
        XCTAssertFalse(app.buttons["suggestedComputation"].exists)
    }
    @MainActor func testUnsupportedAcceptedLatexShowsRecoverableError() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication();app.launchArguments=["--polynomial-ui-test","--polynomial-ui-invalid","--canvas-ui-store",UUID().uuidString];app.launch()
        XCTAssertTrue(app.buttons["recognizeNotebook"].waitForExistence(timeout:20));app.buttons["recognizeNotebook"].tap()
        let action=app.buttons["suggestedComputation"].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout:8));action.tap();waitForMathCompute(app);app.buttons["computeMathToolbar"].tap()
        let error=app.staticTexts["mathError"];revealMath(error,app)
        XCTAssertTrue(error.label.lowercased().contains("unsupported"),error.label)
        XCTAssertFalse(app.staticTexts["integralOutput"].exists)
    }
}
