import XCTest
import PencilKit
@testable import inkpad

final class StrokeLabTests: XCTestCase {
    private func stroke(date: Date = Date(timeIntervalSince1970: 1_700_000_000), transform: CGAffineTransform = .identity) -> PKStroke {
        let points = [
            PKStrokePoint(location: CGPoint(x: 10, y: 20), timeOffset: 0, size: CGSize(width: 2, height: 3), opacity: 1, force: 0.5, azimuth: 0.2, altitude: 1),
            PKStrokePoint(location: CGPoint(x: 30, y: 40), timeOffset: 0.125, size: CGSize(width: 3, height: 4), opacity: 0.8, force: 0.75, azimuth: 0.3, altitude: 1.2)
        ]
        return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: date), transform: transform, mask: nil, randomSeed: 42)
    }
    private func document(_ strokes: [PKStroke]) throws -> StrokeLabDocument {
        var doc = StrokeLabDocument()
        doc.drawing = PKDrawing(strokes: strokes)
        doc.raw = try LabExport.page(from: doc.drawing, preserving: doc.raw)
        return doc
    }
    func testNativeAndPortableRoundTripForEmptyAndSingleStroke() throws {
        for strokes in [[], [stroke()]] {
            let original = try document(strokes)
            let reopened = try StrokeLabDocument(wrapper: original.wrapper())
            XCTAssertEqual(original.raw, reopened.raw)
            XCTAssertEqual(original.annotations, reopened.annotations)
            XCTAssertEqual(reopened.drawing.strokes.count, strokes.count)
        }
    }
    func testExportFidelityAndAffineTransform() throws {
        let transform = CGAffineTransform(a: 0, b: 2, c: -3, d: 0, tx: 100, ty: 200)
        let original = stroke(transform: transform)
        let raw = try document([original]).raw
        let exported = try XCTUnwrap(raw.strokes.first)
        XCTAssertEqual(exported.points.count, original.path.count)
        for (i, point) in exported.points.enumerated() {
            let source = original.path[i]
            XCTAssertEqual(point.x, source.location.x)
            XCTAssertEqual(point.y, source.location.y)
            XCTAssertEqual(point.time, source.timeOffset)
            XCTAssertEqual(point.pressure, Double(source.force))
            XCTAssertEqual(point.azimuth, Double(source.azimuth))
            XCTAssertEqual(point.altitude, Double(source.altitude))
            XCTAssertEqual(point.width, source.size.width)
            XCTAssertEqual(point.height, source.size.height)
            XCTAssertEqual(point.opacity, source.opacity)
            let transformed = exported.transform.apply(x: point.x, y: point.y)
            let expected = source.location.applying(transform)
            XCTAssertEqual(transformed.0, expected.x)
            XCTAssertEqual(transformed.1, expected.y)
        }
        XCTAssertEqual(exported.createdAt, original.path.creationDate.timeIntervalSince1970)
        XCTAssertEqual(exported.bounds.x, original.renderBounds.minX)
        XCTAssertEqual(exported.bounds.width, original.renderBounds.width)
        XCTAssertEqual(exported.ink.rgba, [0,0,0,1])
        let unmoved = try document([stroke()]).raw.strokes[0]
        XCTAssertEqual(exported.id, unmoved.id, "Transform is not part of identity")
    }
    func testStableMembershipAfterDiskReopening() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try StrokeLabStore(directory: directory)
        var doc = try document([stroke()])
        let group = LabGroup(label: "Expression", strokeIDs: doc.raw.strokes.map(\.id))
        doc.annotations.groups = [group]
        doc.annotations.record("Create expression", author: "test")
        try store.save(doc)
        let reopened = try store.open(XCTUnwrap(store.pages().first))
        XCTAssertEqual(reopened.annotations.groups, [group])
        XCTAssertEqual(reopened.raw.strokes.map(\.id), doc.raw.strokes.map(\.id))
        // Atomic replacement must work for repeated saves of the same page.
        try store.save(reopened)
        XCTAssertEqual(try store.pages().count, 1)
    }
    func testErasingRewritingAndReconciliation() throws {
        var doc = try document([stroke()])
        let oldID = doc.raw.strokes[0].id
        doc.annotations.groups = [LabGroup(label: "Expression", strokeIDs: [oldID])]
        doc.annotations.record("Create expression", author: "test")
        doc.raw = try LabExport.page(from: PKDrawing(), preserving: doc.raw)
        doc.annotations.reconcile(existing: [], author: "test")
        XCTAssertTrue(doc.annotations.groups[0].strokeIDs.isEmpty)
        let rewrite = PKDrawing(strokes: [stroke(date: Date(timeIntervalSince1970: 1_700_000_001))])
        doc.raw = try LabExport.page(from: rewrite, preserving: doc.raw)
        XCTAssertNotEqual(oldID, doc.raw.strokes[0].id)
        XCTAssertTrue(doc.annotations.groups[0].strokeIDs.isEmpty)
        try LabValidation.validate(raw: doc.raw, annotations: doc.annotations)
    }
    func testSplitMergeAndUnassign() throws {
        let doc = try document((0..<3).map { stroke(date: Date(timeIntervalSince1970: Double($0))) })
        let ids = doc.raw.strokes.map(\.id)
        var annotations = doc.annotations
        let group = LabGroup(label: "Expression", strokeIDs: ids)
        annotations.groups = [group]
        annotations.record("Create expression", author: "test")
        try annotations.split([ids[0]], from: group.id, author: "test")
        XCTAssertEqual(annotations.groups.count, 2)
        XCTAssertEqual(annotations.groups[0].strokeIDs.count, 2)
        try annotations.merge(Set(annotations.groups.map(\.id)), author: "test")
        XCTAssertEqual(Set(annotations.groups[0].strokeIDs), Set(ids))
        annotations.assign([ids[1]], to: nil, author: "test")
        XCTAssertEqual(annotations.groups[0].strokeIDs.count, 2)
        try LabValidation.validate(raw: doc.raw, annotations: annotations)
        XCTAssertThrowsError(try annotations.split([], from: group.id, author: "test"))
        XCTAssertThrowsError(try annotations.merge([group.id], author: "test"))
    }
    func testInvalidAnnotationsAndNestedRows() throws {
        let doc = try document([stroke()])
        let id = doc.raw.strokes[0].id
        var annotations = doc.annotations
        annotations.groups = [LabGroup(label: "Invalid", strokeIDs: ["missing"])]
        XCTAssertThrowsError(try LabValidation.validate(raw: doc.raw, annotations: annotations))
        annotations.groups = [LabGroup(label: "A", strokeIDs: [id]), LabGroup(label: "B", strokeIDs: [id])]
        XCTAssertThrowsError(try LabValidation.validate(raw: doc.raw, annotations: annotations))
        let parent = LabRow(label: "Numerator", strokeIDs: [id])
        var child = LabRow(label: "Nested", parentRowID: parent.id, strokeIDs: [id])
        annotations.groups = [LabGroup(label: "A", strokeIDs: [id], rows: [parent, child])]
        try LabValidation.validate(raw: doc.raw, annotations: annotations)
        annotations.assign([id], to: annotations.groups[0].id, author: "test")
        XCTAssertEqual(annotations.groups[0].rows, [parent, child], "Assigning to the same expression preserves rows")
        child.parentRowID = child.id
        annotations.groups[0].rows = [parent, child]
        XCTAssertThrowsError(try LabValidation.validate(raw: doc.raw, annotations: annotations))
        annotations.groups[0].rows = [LabRow(label: "Missing parent", parentRowID: "missing", strokeIDs: [id])]
        XCTAssertThrowsError(try LabValidation.validate(raw: doc.raw, annotations: annotations))
    }
    func testInvalidTimingDuplicateIdentitiesAndSchema() throws {
        var doc = try document([stroke()])
        doc.raw.strokes[0].points[1].time = -1
        XCTAssertThrowsError(try doc.validate())
        let duplicate = try document([stroke(), stroke()])
        XCTAssertThrowsError(try duplicate.wrapper())
        let valid = try document([stroke()])
        let encoder = JSONEncoder()
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(valid.raw)) as? [String: Any])
        raw["unexpected"] = true
        XCTAssertThrowsError(try StrokeLabSchema.validate(raw: JSONSerialization.data(withJSONObject: raw), annotations: encoder.encode(valid.annotations)))
        raw.removeValue(forKey: "unexpected")
        raw.removeValue(forKey: "schemaVersion")
        XCTAssertThrowsError(try StrokeLabSchema.validate(raw: JSONSerialization.data(withJSONObject: raw), annotations: encoder.encode(valid.annotations)))
    }
    func testCorruptOrMismatchedNativePackageIsRejected() throws {
        let doc = try document([stroke()])
        let wrapper = try doc.wrapper()
        wrapper.removeFileWrapper(try XCTUnwrap(wrapper.fileWrappers?["drawing.pkdrawing"]))
        wrapper.addRegularFile(withContents: PKDrawing().dataRepresentation(), preferredFilename: "drawing.pkdrawing")
        XCTAssertThrowsError(try StrokeLabDocument(wrapper: wrapper))
        wrapper.removeFileWrapper(try XCTUnwrap(wrapper.fileWrappers?["annotations.json"]))
        XCTAssertThrowsError(try StrokeLabDocument(wrapper: wrapper))
    }
    func testMaskedInkIsRejectedRatherThanExportingErasedPoints() throws {
        let original = stroke()
        let masked = PKStroke(ink: original.ink, path: original.path, transform: .identity, mask: UIBezierPath(rect: CGRect(x: 0, y: 0, width: 20, height: 30)))
        XCTAssertThrowsError(try document([masked]))
    }
}
