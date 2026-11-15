import XCTest

final class ExpressionWorkflowUITests:XCTestCase {
    override func setUpWithError() throws { continueAfterFailure=false }
    @MainActor private func launch(empty:Bool=false,extra:[String]=[])->XCUIApplication {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication();app.launchArguments=["--polynomial-ui-test","--inline-ui-test","--canvas-ui-store",UUID().uuidString,"-recognition.automaticallyRecognize","YES"]
        app.launchArguments += extra
        if empty { app.launchArguments.append("--canvas-empty-ui") }
        app.launch();XCTAssertTrue(app.buttons["recognizeNotebook"].waitForExistence(timeout:15));return app
    }
    @MainActor private func chip(_ app:XCUIApplication)->XCUIElement {
        app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","expressionIndicator-")).firstMatch
    }
    @MainActor private func reveal(_ element:XCUIElement,_ app:XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable {return}
            if app.collectionViews["mathWorkbenchForm"].exists { app.collectionViews["mathWorkbenchForm"].swipeUp() }
            else {
                let scroll=app.scrollViews["inlineInspectorScroll"]
                if element.exists && element.frame.minY<scroll.frame.midY {scroll.swipeDown()} else {scroll.swipeUp()}
            }
        }
        if !element.isHittable { print(app.debugDescription) }
        XCTAssertTrue(element.isHittable)
    }
    @MainActor func testInlineReviewSolveTargetInsertAndReopen() {
        let app=launch(),indicator=chip(app)
        XCTAssertTrue(indicator.waitForExistence(timeout:10));XCTAssertEqual(indicator.value as? String,"review");indicator.tap()
        let accept=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","acceptExpression-")).firstMatch
        app.buttons["Edit recognition"].tap()
        let editor=app.textViews.matching(NSPredicate(format:"identifier BEGINSWITH %@","latexEditor-")).firstMatch
        app.buttons["clearRecognitionDraft"].tap();reveal(editor,app);editor.tap();editor.typeText("x^2+1=0")
        XCTAssertEqual(editor.value as? String,"x^2+1=0")
        app.scrollViews["inlineInspectorScroll"].swipeDown()
        reveal(accept,app);accept.tap()
        let solve=app.buttons["suggestedComputation"];reveal(solve,app);XCTAssertEqual(solve.label,"Solve equation");solve.tap()
        XCTAssertTrue(app.staticTexts["mathTargetLatex"].waitForExistence(timeout:5));XCTAssertEqual(app.staticTexts["mathTargetLatex"].label,"x^2+1=0")
        // Opening a command preview must not compute or insert anything.
        XCTAssertFalse(app.staticTexts["integralOutput"].exists)
        waitForMathCompute(app);app.buttons["computeMathToolbar"].tap()
        let output=app.collectionViews["mathWorkbenchForm"].staticTexts["integralOutput"].firstMatch;reveal(output,app)
        XCTAssertEqual(output.label,#"x = \pm i"#)
        let insert=app.collectionViews["mathWorkbenchForm"].buttons["insertIntegralResult"].firstMatch;reveal(insert,app);insert.tap()
        let card=app.descendants(matching:.any).matching(identifier:"insertedCanvasResult").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout:15));XCTAssertEqual(chip(app).value as? String,"accepted")
        app.terminate();app.launch();XCTAssertTrue(card.waitForExistence(timeout:15));XCTAssertEqual(chip(app).value as? String,"accepted")
    }
    @MainActor func testInlineAcceptWithoutOpeningInspector() {
        let app=launch(extra:["--narrow-window-ui"])
        let accept=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","inlineAcceptExpression-")).firstMatch
        XCTAssertTrue(accept.waitForExistence(timeout:20))
        let ready=NSPredicate(format:"enabled == true")
        expectation(for:ready,evaluatedWith:accept);waitForExpectations(timeout:20)
        XCTAssertFalse(app.buttons["closeExpressionInspector"].exists)
        let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name="Inline recognition preview";attachment.lifetime = .keepAlways;add(attachment)
        accept.tap();XCTAssertEqual(chip(app).value as? String,"accepted")
        XCTAssertFalse(accept.exists)
        app.terminate();app.launch();XCTAssertEqual(chip(app).value as? String,"accepted")
    }
    @MainActor func testSidePreviewsExpandScrollAndAcceptIndependently() {
        let app=launch(extra:["--pending-rows-ui"])
        let chips=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","expressionIndicator-"))
        XCTAssertTrue(chips.element(boundBy:1).waitForExistence(timeout:15))
        let top=chips.element(boundBy:0),rowID=String(top.identifier.dropFirst("expressionIndicator-".count))
        let otherID=String(chips.element(boundBy:1).identifier.dropFirst("expressionIndicator-".count))
        XCTAssertGreaterThan(top.frame.minX,app.scrollViews["notebookInkCanvas"].frame.midX)
        let accept=app.buttons["inlineAcceptExpression-"+rowID]
        XCTAssertTrue(accept.waitForExistence(timeout:20));XCTAssertLessThan(top.frame.maxY,accept.frame.minY)
        app.buttons["expandMathPreview-"+rowID].tap()
        XCTAssertTrue(app.scrollViews["expandedMathScroll"].waitForExistence(timeout:20))
        XCTAssertTrue(app.buttons["Shrink preview"].exists)
        expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:accept);waitForExpectations(timeout:20)
        accept.tap()
        XCTAssertEqual(app.buttons["expressionIndicator-"+rowID].value as? String,"accepted")
        XCTAssertEqual(app.buttons["expressionIndicator-"+otherID].value as? String,"review")
    }
    @MainActor func testWideSidePreviewCanExpandScrollAndShrink() {
        let app=launch(extra:["--wide-inline-preview-ui"])
        let indicator=chip(app);XCTAssertTrue(indicator.waitForExistence(timeout:15))
        let id=String(indicator.identifier.dropFirst("expressionIndicator-".count))
        let expand=app.buttons["expandMathPreview-"+id],accept=app.buttons["inlineAcceptExpression-"+id]
        XCTAssertTrue(accept.waitForExistence(timeout:20));expectation(for:NSPredicate(format:"enabled == true"),evaluatedWith:accept);waitForExpectations(timeout:20)
        expand.tap();let scroll=app.scrollViews["expandedMathScroll"];XCTAssertTrue(scroll.waitForExistence(timeout:5))
        XCTAssertGreaterThan(scroll.frame.width,220);XCTAssertTrue(app.buttons["expressionIndicator-"+id].isHittable);scroll.swipeLeft();scroll.swipeRight()
        let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name="Expanded scrolling side preview";attachment.lifetime = .keepAlways;add(attachment)
        app.buttons["Shrink preview"].tap();XCTAssertFalse(scroll.exists)
        XCTAssertTrue(accept.isHittable)
    }
    @MainActor func testSideRailScrollUpdatesHitTargetsAndLeavesCanvasWritable() {
        let app=launch(extra:["--many-pending-rows-ui"])
        let accepts=app.buttons.matching(NSPredicate(format:"identifier BEGINSWITH %@","inlineAcceptExpression-"))
        XCTAssertTrue(accepts.firstMatch.waitForExistence(timeout:20))
        let initial=Set(accepts.allElementsBoundByIndex.filter(\.isHittable).map(\.identifier))
        let rail=app.scrollViews["recognitionSideRail"],start=rail.coordinate(withNormalizedOffset:CGVector(dx:0.93,dy:0.65))
        start.press(forDuration:0.05,thenDragTo:start.withOffset(CGVector(dx:0,dy:-450)))
        guard let target=accepts.allElementsBoundByIndex.last(where:{$0.isHittable}) else {XCTFail("No lower preview was reachable after scrolling");return}
        XCTAssertFalse(initial.contains(target.identifier),"Scrolling must reveal a previously offscreen preview")
        let id=String(target.identifier.dropFirst("inlineAcceptExpression-".count))
        expectation(for:NSPredicate(format:"enabled == true AND hittable == true"),evaluatedWith:target);waitForExpectations(timeout:20)
        let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name="Scrolled dense side rail";attachment.lifetime = .keepAlways;add(attachment)
        app.buttons["expandMathPreview-"+id].tap();XCTAssertTrue(app.scrollViews["expandedMathScroll"].waitForExistence(timeout:5))
        app.buttons["Shrink preview"].tap();XCTAssertTrue(target.isHittable,"Shrinking must preserve the rail position")
        target.tap();XCTAssertEqual(app.buttons["expressionIndicator-"+id].value as? String,"accepted")
        let canvas=app.scrollViews["notebookInkCanvas"],before=canvas.value as? String
        let ink=canvas.coordinate(withNormalizedOffset:CGVector(dx:0.3,dy:0.8))
        ink.press(forDuration:0.05,thenDragTo:ink.withOffset(CGVector(dx:60,dy:25)))
        XCTAssertNotEqual(canvas.value as? String,before)
    }
    @MainActor func testAutomaticRecognitionLeavesCanvasWritableAndDoesNotOpenPreview() {
        let app=launch(empty:true),canvas=app.scrollViews["notebookInkCanvas"]
        XCTAssertFalse(chip(app).exists)
        let start=canvas.coordinate(withNormalizedOffset:CGVector(dx:0.25,dy:0.3))
        start.press(forDuration:0.05,thenDragTo:start.withOffset(CGVector(dx:70,dy:30)))
        let indicator=chip(app);let found=indicator.waitForExistence(timeout:10);if !found {print(app.debugDescription)};XCTAssertTrue(found);XCTAssertEqual(indicator.value as? String,"review")
        XCTAssertFalse(app.otherElements["recognitionRows"].exists)
        let previous=canvas.value as? String
        let next=canvas.coordinate(withNormalizedOffset:CGVector(dx:0.7,dy:0.65))
        next.press(forDuration:0.05,thenDragTo:next.withOffset(CGVector(dx:70,dy:25)))
        XCTAssertNotEqual(previous,canvas.value as? String,"Indicator overlay must pass blank-page touches to PencilKit")
        app.buttons["tool-eraser"].tap()
        next.press(forDuration:0.05,thenDragTo:next.withOffset(CGVector(dx:70,dy:25)))
        app.buttons["undoCanvas"].tap()
    }
}
