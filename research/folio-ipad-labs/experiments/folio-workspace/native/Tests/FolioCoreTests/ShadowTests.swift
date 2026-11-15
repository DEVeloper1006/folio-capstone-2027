import Foundation
import FolioCore

private func XCTAssertNil<T>(_ value: T?) { precondition(value == nil) }
private func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T) { precondition(a == b, "\(a) != \(b)") }
private func XCTAssertTrue(_ value: Bool) { precondition(value) }
private func XCTAssertFalse(_ value: Bool) { precondition(!value) }
private func XCTFail(_ message: String) { preconditionFailure(message) }
private func XCTAssertThrowsError<T>(_ value: @autoclosure () throws -> T) {
    do { _ = try value(); preconditionFailure("Expected error") } catch {}
}

@main struct ShadowTests {
    static func main() throws {
        let tests = ShadowTests()
        tests.testUnknownAndAmbiguousBarStayInk()
        tests.testEqualsAndPlus()
        tests.testFractionKeepsUnknownChildren()
        tests.testPersonalTemplateTranslationAndScale()
        tests.testConflictingTemplatesRemainInk()
        tests.testSeparateRowsAndStableIdentity()
        tests.testLargeHandwritingAndDetachedMarks()
        tests.testStaleRequestsRejected()
        try tests.testPersistencePreservesAcceptedSource()
        tests.testInvalidCoordinatesRejected()
        print("10 FolioCore checks passed")
    }
    func stroke(_ points: [(Double, Double)]) -> InkStroke {
        InkStroke(points: points.map { InkPoint(x: $0.0, y: $0.1) })
    }
    func testUnknownAndAmbiguousBarStayInk() {
        let s = stroke([(10,20),(60,20)])
        XCTAssertNil(ShadowRecognizer().parse([s]).latex)
        XCTAssertEqual(ShadowRecognizer().parse([s]), .row([.ink([s])]))
    }
    func testEqualsAndPlus() {
        let h = stroke([(10,20),(50,20)])
        let h2 = stroke([(10,30),(50,30)])
        XCTAssertEqual(ShadowRecognizer().parse([h,h2]).latex, "=")
        let v = stroke([(30,5),(30,35)])
        XCTAssertEqual(ShadowRecognizer().parse([h,v]).latex, "+")
    }
    func testFractionKeepsUnknownChildren() {
        let top = stroke([(30,10),(30,25)])
        let bar = stroke([(10,40),(70,40)])
        let bottom = stroke([(30,55),(30,70)])
        let node = ShadowRecognizer().parse([top,bar,bottom])
        guard case .fraction(_, _, let id) = node else { return XCTFail("Expected fraction") }
        XCTAssertEqual(id, bar.id)
        XCTAssertNil(node.latex)
    }
    func testPersonalTemplateTranslationAndScale() {
        let example = stroke([(10,10),(30,30),(10,50)])
        let incoming = stroke([(100,100),(140,140),(100,180)])
        let engine = ShadowRecognizer(examples: [InkExample(latex: "7", strokes: [example])])
        XCTAssertEqual(engine.parse([incoming]).latex, "7")
    }
    func testConflictingTemplatesRemainInk() {
        let s = stroke([(10,10),(30,30),(10,50)])
        let engine = ShadowRecognizer(examples: [InkExample(latex: "x", strokes: [s]), InkExample(latex: "y", strokes: [s])])
        XCTAssertNil(engine.parse([s]).latex)
    }
    func testSeparateRowsAndStableIdentity() {
        let a = stroke([(10,20),(50,20)]), b = stroke([(10,200),(50,200)])
        let engine = ShadowRecognizer()
        XCTAssertEqual(engine.regions([a,b]).count, 2)
        XCTAssertEqual(engine.regions([a,b]), engine.regions([b,a]))
    }
    func testLargeHandwritingAndDetachedMarks() {
        let main = stroke([(10,200),(70,100),(140,200)])
        let mark = stroke([(80,30),(90,35)])
        let rows = ShadowRecognizer().regions([main, mark])
        XCTAssertEqual(rows.count, 2)
        let largeMain = stroke([(10,220),(200,700)])
        let hat = stroke([(50,140),(100,20),(150,140)])
        XCTAssertEqual(ShadowRecognizer().regions([largeMain, hat]).count, 1)
        let secondRow = stroke([(10,400),(70,300),(140,400)])
        XCTAssertEqual(ShadowRecognizer().regions([main, secondRow]).count, 2)
    }
    func testStaleRequestsRejected() {
        let id = UUID(), s = stroke([(10,20),(50,20)])
        let ticket = RecognitionTicket(documentID: id, revision: 1, strokes: [s])
        XCTAssertTrue(ticket.matches(documentID: id, revision: 1, strokes: [s]))
        XCTAssertFalse(ticket.matches(documentID: id, revision: 2, strokes: [s]))
        XCTAssertFalse(ticket.matches(documentID: UUID(), revision: 1, strokes: [s]))
        var changed = s; changed.points[0].x += 1
        XCTAssertFalse(ticket.matches(documentID: id, revision: 1, strokes: [changed]))
    }
    func testPersistencePreservesAcceptedSource() throws {
        var doc = InkDocument()
        doc.strokes = [stroke([(10,10),(20,20)])]
        doc.expressions = [AcceptedExpression(latex: "x", provider: "user-reviewed", sourceStrokes: doc.strokes)]
        let restored = try InkDocument.decode(doc.encoded())
        XCTAssertEqual(restored.strokes, doc.strokes)
        XCTAssertEqual(restored.expressions[0].sourceStrokes, doc.strokes)
    }
    func testInvalidCoordinatesRejected() {
        var doc = InkDocument(); doc.strokes = [stroke([(-1,10),(20,20)])]
        XCTAssertThrowsError(try doc.encoded())
    }
}
