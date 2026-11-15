import XCTest

@MainActor
extension XCTestCase {
    func waitForMathCompute(_ app:XCUIApplication,file:StaticString=#filePath,line:UInt=#line) {
        let compute=app.buttons["computeMathToolbar"]
        XCTAssertTrue(compute.waitForExistence(timeout:8),file:file,line:line)
        let ready=XCTNSPredicateExpectation(predicate:NSPredicate(format:"enabled == true"),object:compute)
        XCTAssertEqual(XCTWaiter.wait(for:[ready],timeout:16),.completed,file:file,line:line)
    }
    func reviewMathInputs(_ app:XCUIApplication) {
        let button=app.buttons["reviewMathInputs"]
        XCTAssertTrue(button.waitForExistence(timeout:5));button.tap();waitForMathCompute(app)
    }
    func revealMath(_ element:XCUIElement,_ app:XCUIApplication) {
        for _ in 0..<9 { if element.exists && element.isHittable{return};app.collectionViews["mathWorkbenchForm"].swipeUp() }
        if !element.isHittable {print(app.debugDescription)}
        XCTAssertTrue(element.isHittable)
    }
    func chooseMath(_ title:String,category:String,in app:XCUIApplication) {
        if app.buttons["changeMathOperation"].exists {app.buttons["changeMathOperation"].tap()}
        else if app.buttons["anotherRowComputation"].exists {app.buttons["anotherRowComputation"].tap()}
        let topics=app.segmentedControls["mathCategory"],form=app.collectionViews["mathWorkbenchForm"]
        for _ in 0..<6 {if topics.exists && topics.isHittable{break};form.swipeDown()}
        topics.buttons[category].tap();app.buttons["mathOperation"].tap()
        let item=app.buttons[title].firstMatch;XCTAssertTrue(item.waitForExistence(timeout:5));item.tap();reviewMathInputs(app)
    }
}
