import XCTest

final class CanvasUITests:XCTestCase {
    override func setUpWithError() throws { continueAfterFailure=false }
    @MainActor
    private func app(empty:Bool=false)->XCUIApplication {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication();app.launchArguments=["--polynomial-ui-test","--canvas-ui-store",UUID().uuidString,"-AppleInterfaceStyle","Dark"]
        if empty { app.launchArguments.append("--canvas-empty-ui") }
        app.launch();XCTAssertTrue(app.buttons["tool-pen"].waitForExistence(timeout:20));return app
    }
    @MainActor
    private func enabled(_ element:XCUIElement,_ value:Bool) {
        let expectation=XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == %@",NSNumber(value:value)),object:element)
        XCTAssertEqual(XCTWaiter.wait(for:[expectation],timeout:5),.completed)
    }
    @MainActor
    func testDifferentToolSelectsAndRepeatedTapOpensOptions() {
        let app=app()
        app.buttons["tool-eraser"].tap()
        XCTAssertFalse(app.sliders["toolThickness"].exists)
        app.buttons["tool-eraser"].tap()
        XCTAssertTrue(app.sliders["toolThickness"].waitForExistence(timeout:3))
        app.buttons["tool-pen"].tap()
        XCTAssertFalse(app.sliders["toolThickness"].exists)
        app.buttons["tool-pen"].tap()
        XCTAssertTrue(app.sliders["toolThickness"].waitForExistence(timeout:3))
    }
    @MainActor
    func testToolSlidersBlackInkAndNativeUndoRedo() {
        let app=app()
        for name in ["pen","highlighter","eraser"] {
            app.buttons["tool-"+name].tap()
            let slider=app.sliders["toolThickness"]
            if !slider.exists { app.buttons["tool-"+name].tap() }
            XCTAssertTrue(slider.waitForExistence(timeout:5));slider.adjust(toNormalizedSliderPosition:0.4)
            XCTAssertTrue(app.staticTexts["thicknessValue"].exists)
            if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        }
        XCTAssertTrue(app.descendants(matching:.any)["inkColourPicker"].firstMatch.exists)
        app.buttons["ink-black"].tap();app.buttons["tool-pen"].tap();if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        let canvas=app.scrollViews["notebookInkCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout:5))
        let original=canvas.value as? String
        let start=canvas.coordinate(withNormalizedOffset:CGVector(dx:0.35,dy:0.35))
        let end=canvas.coordinate(withNormalizedOffset:CGVector(dx:0.55,dy:0.55))
        start.press(forDuration:0.05,thenDragTo:end)
        let undo=app.buttons["undoCanvas"],redo=app.buttons["redoCanvas"]
        enabled(undo,true);let drawn=canvas.value as? String;XCTAssertNotEqual(drawn,original)
        undo.tap();enabled(redo,true);XCTAssertEqual(canvas.value as? String,original)
        redo.tap();XCTAssertEqual(canvas.value as? String,drawn)
        let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name="Black ink and live tool controls";attachment.lifetime = .keepAlways;add(attachment)
    }
    @MainActor
    func testDrawWithoutDismissingOptionsEraseUndoAndDrawAgain() {
        let app=app(),canvas=app.scrollViews["notebookInkCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout:5))
        let initial=canvas.value as? String
        app.buttons["tool-pen"].tap()
        let panelAppeared=app.sliders["toolThickness"].waitForExistence(timeout:5)
        if !panelAppeared { print(app.debugDescription) }
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Pen tool options";shot.lifetime = .keepAlways;add(shot)
        XCTAssertTrue(panelAppeared)
        let start=canvas.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.6))
        let end=start.withOffset(CGVector(dx:100,dy:0))
        start.press(forDuration:0.05,thenDragTo:end)
        let drawn=canvas.value as? String
        XCTAssertNotEqual(drawn,initial)
        XCTAssertFalse(app.sliders["toolThickness"].exists)
        app.buttons["tool-eraser"].tap();app.buttons["tool-eraser"].tap()
        app.sliders["toolThickness"].adjust(toNormalizedSliderPosition:0.8)
        // No Done tap: the first gesture must really erase, not dismiss a modal.
        start.press(forDuration:0.05,thenDragTo:end)
        XCTAssertTrue(canvas.label.contains("eraser"),canvas.label)
        let erasedExpectation=XCTNSPredicateExpectation(predicate:NSPredicate(format:"value != %@",drawn!),object:canvas)
        let didErase=XCTWaiter.wait(for:[erasedExpectation],timeout:5)
        if didErase != .completed { print(app.debugDescription) }
        let eraserShot=XCTAttachment(screenshot:app.screenshot());eraserShot.name="After eraser gesture";eraserShot.lifetime = .keepAlways;add(eraserShot)
        XCTAssertEqual(didErase,.completed)
        let erased=canvas.value as? String
        XCTAssertNotEqual(erased,drawn)
        let undo=app.buttons["undoCanvas"],redo=app.buttons["redoCanvas"]
        enabled(undo,true);undo.tap();XCTAssertEqual(canvas.value as? String,drawn)
        redo.tap();XCTAssertEqual(canvas.value as? String,erased)
        app.buttons["tool-highlighter"].tap()
        let markerStart=start.withOffset(CGVector(dx:0,dy:80))
        markerStart.press(forDuration:0.05,thenDragTo:markerStart.withOffset(CGVector(dx:100,dy:0)))
        XCTAssertNotEqual(canvas.value as? String,erased)
        app.buttons["tool-pen"].tap()
        start.press(forDuration:0.05,thenDragTo:end)
        enabled(undo,true)
    }
    @MainActor
    func testNativeLassoCanSelectMoveAndUndoInk() {
        let app=app(),canvas=app.scrollViews["notebookInkCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout:5))
        let start=canvas.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.6))
        let end=start.withOffset(CGVector(dx:100,dy:0))
        start.press(forDuration:0.05,thenDragTo:end)
        let drawn=canvas.value as? String
        app.buttons["tool-lasso"].tap();if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        let center=start.withOffset(CGVector(dx:50,dy:0))
        center.press(forDuration:1.2)
        center.press(forDuration:0.1,thenDragTo:center.withOffset(CGVector(dx:0,dy:100)))
        XCTAssertNotEqual(canvas.value as? String,drawn,"Native lasso must move the ink, not just change the toolbar")
        app.buttons["undoCanvas"].tap();XCTAssertEqual(canvas.value as? String,drawn)
    }
    @MainActor
    func testEmptyPageCanDrawEraseAllAndDrawAgain() {
        let app=app(empty:true),canvas=app.scrollViews["notebookInkCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout:5))
        XCTAssertTrue((canvas.value as? String)?.hasPrefix("0 strokes") == true)
        let start=canvas.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.6)),end=start.withOffset(CGVector(dx:100,dy:0))
        start.press(forDuration:0.05,thenDragTo:end)
        XCTAssertTrue((canvas.value as? String)?.hasPrefix("1 strokes") == true)
        app.buttons["tool-eraser"].tap();app.buttons["tool-eraser"].tap();app.sliders["toolThickness"].adjust(toNormalizedSliderPosition:0.9)
        start.press(forDuration:0.05,thenDragTo:end)
        let empty=XCTNSPredicateExpectation(predicate:NSPredicate(format:"value BEGINSWITH %@","0 strokes"),object:canvas)
        XCTAssertEqual(XCTWaiter.wait(for:[empty],timeout:5),.completed)
        app.buttons["tool-pen"].tap()
        start.press(forDuration:0.05,thenDragTo:end)
        XCTAssertTrue((canvas.value as? String)?.hasPrefix("1 strokes") == true)
        app.buttons["undoCanvas"].tap()
        XCTAssertTrue((canvas.value as? String)?.hasPrefix("0 strokes") == true)
        app.buttons["redoCanvas"].tap()
        XCTAssertTrue((canvas.value as? String)?.hasPrefix("1 strokes") == true)
    }
    @MainActor
    func testLibraryNavigationKeepsPenEraserAndLassoConnected() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app=XCUIApplication()
        app.launchArguments=["--polynomial-ui-test","--canvas-ui-store",UUID().uuidString,"--canvas-library-ui","--canvas-empty-ui","-AppleInterfaceStyle","Dark"]
        app.launch()
        let notebook=app.buttons.matching(NSPredicate(format:"label CONTAINS %@","Polynomial integration test")).firstMatch
        XCTAssertTrue(notebook.waitForExistence(timeout:15));notebook.tap()
        let canvas=app.scrollViews["notebookInkCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout:5))
        let start=canvas.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.6)),end=canvas.coordinate(withNormalizedOffset:CGVector(dx:0.65,dy:0.6))
        for tool in ["pen","eraser","pen","highlighter","pen","lasso"] {
            app.buttons["tool-"+tool].tap()
            if app.buttons["Done"].exists { if app.buttons["Done"].exists { app.buttons["Done"].tap() } }
            XCTAssertTrue(canvas.label.contains(tool == "eraser" ? "eraser":tool == "lasso" ? "lasso":"ink"),canvas.label)
            if tool != "lasso" {
                let before=canvas.value as? String
                start.press(forDuration:0.05,thenDragTo:end)
                let changed=XCTNSPredicateExpectation(predicate:NSPredicate(format:"value != %@",before!),object:canvas)
                XCTAssertEqual(XCTWaiter.wait(for:[changed],timeout:5),.completed,"Tool failed after library navigation: "+tool)
            }
        }
        let before=canvas.value as? String
        let center=start.withOffset(CGVector(dx:40,dy:0))
        center.press(forDuration:1.2)
        center.press(forDuration:0.1,thenDragTo:center.withOffset(CGVector(dx:0,dy:100)))
        XCTAssertNotEqual(canvas.value as? String,before)
    }
    @MainActor
    func testInsertUndoDragAndReopenResult() {
        let app=app();app.buttons["recognizeNotebook"].tap()
        let integrate=app.buttons["suggestedComputation"].firstMatch
        XCTAssertTrue(integrate.waitForExistence(timeout:10));integrate.tap()
        waitForMathCompute(app);app.buttons["computeMathToolbar"].tap()
        let insert=app.buttons["insertIntegralResult"].firstMatch,rows=app.scrollViews["recognitionRows"]
        XCTAssertTrue(insert.waitForExistence(timeout:8))
        for _ in 0..<5 { if insert.isHittable { break };rows.swipeUp() }
        XCTAssertTrue(insert.isEnabled);insert.tap()
        let tile=app.descendants(matching:.any).matching(identifier:"insertedCanvasResult").firstMatch
        let appeared=tile.waitForExistence(timeout:15)
        if !appeared { print(app.debugDescription);let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Insertion diagnostic";shot.lifetime = .keepAlways;add(shot) }
        XCTAssertTrue(appeared)
        let undo=app.buttons["undoCanvas"],redo=app.buttons["redoCanvas"]
        enabled(undo,true);undo.tap()
        let absent=XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"),object:tile)
        XCTAssertEqual(XCTWaiter.wait(for:[absent],timeout:5),.completed)
        redo.tap();XCTAssertTrue(tile.waitForExistence(timeout:5))
        app.buttons["tool-lasso"].tap();if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        let before=tile.frame
        let point=tile.coordinate(withNormalizedOffset:CGVector(dx:0.25,dy:0.08))
        point.press(forDuration:0.1,thenDragTo:point.withOffset(CGVector(dx:140,dy:80)))
        let moved=tile.frame
        XCTAssertGreaterThan(moved.minX,before.minX+100);XCTAssertGreaterThan(moved.minY,before.minY+40)
        undo.tap();XCTAssertEqual(tile.frame.minX,before.minX,accuracy:3)
        redo.tap();XCTAssertEqual(tile.frame.minX,moved.minX,accuracy:3)
        let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name="Inserted movable integral";attachment.lifetime = .keepAlways;add(attachment)
        app.buttons["tool-pen"].tap();if app.buttons["Done"].exists { app.buttons["Done"].tap() }
        let canvas=app.scrollViews["notebookInkCanvas"]
        let original=canvas.value as? String
        let inkStart=canvas.coordinate(withNormalizedOffset:CGVector(dx:0.72,dy:0.65))
        inkStart.press(forDuration:0.05,thenDragTo:inkStart.withOffset(CGVector(dx:90,dy:45)))
        XCTAssertNotEqual(canvas.value as? String,original)
        undo.tap();XCTAssertEqual(canvas.value as? String,original)
        app.terminate();app.launch()
        XCTAssertTrue(tile.waitForExistence(timeout:15))
        XCTAssertEqual(tile.frame.minX,moved.minX,accuracy:4);XCTAssertEqual(tile.frame.minY,moved.minY,accuracy:4)
    }
}
