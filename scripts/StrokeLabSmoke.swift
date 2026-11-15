// Synthetic strokes only. Compile with the production contract, schema, and document files.
import Foundation
import PencilKit
import AppKit

@main
struct StrokeLabSmoke {
    static func main() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            if !condition() { throw LabError.invalid("Smoke check failed: " + message) }
        }
        func rejects(_ message: String, _ operation: () throws -> Void) throws {
            do { try operation() } catch { return }
            throw LabError.invalid("Expected rejection: " + message)
        }
        func stroke(_ time: Double, transform: CGAffineTransform = .identity) -> PKStroke {
            let points = [CGPoint(x: 10.0314159, y: 20.271828), CGPoint(x: 40.123456, y: 60.987654)].enumerated().map { index, location in
                PKStrokePoint(location: location, timeOffset: Double(index) * 0.125,
                              size: CGSize(width: 2.314159, height: 3.271828), opacity: 0.876543, force: 0.5,
                              azimuth: 0.234567, altitude: 1.123456)
            }
            return PKStroke(ink: PKInk(.pen, color: .black), path: PKStrokePath(controlPoints: points, creationDate: Date(timeIntervalSince1970: time)), transform: transform, mask: nil, randomSeed: 42)
        }
        func document(_ strokes: [PKStroke]) throws -> StrokeLabDocument {
            var doc = StrokeLabDocument()
            doc.drawing = PKDrawing(strokes: strokes)
            doc.raw = try LabExport.page(from: doc.drawing, preserving: doc.raw)
            return doc
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("folio-smoke-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try StrokeLabStore(directory: directory)
        for strokes in [[], [stroke(100)], [stroke(100), stroke(101)], [stroke(Date().timeIntervalSince1970)]] {
            var doc = try document(strokes)
            if !strokes.isEmpty {
                let ids = doc.raw.strokes.map(\.id)
                let parent = LabRow(label: "Visual row", strokeIDs: ids)
                let child = LabRow(label: "Nested row", parentRowID: parent.id, strokeIDs: [ids[0]])
                doc.annotations.groups = [LabGroup(label: "Expression", strokeIDs: ids, rows: [parent, child])]
                doc.annotations.record("Create expression", author: "synthetic-test")
            }
            print("Checking save/reopen for \(strokes.count) strokes")
            try store.save(doc)
            print("Saved package")
            let url = directory.appendingPathComponent(doc.raw.pageID).appendingPathExtension("folioink")
            let reopened = try store.open(url)
            try check(reopened.raw == doc.raw, "Native/raw round-trip")
            try check(reopened.annotations == doc.annotations, "Annotation round-trip")
            try check(reopened.drawing.strokes.count == strokes.count, "Native stroke count")
            try store.save(reopened)
            print("PASS native export, schema, annotations, atomic save/reopen: \(strokes.count) strokes")
        }
        let transform = CGAffineTransform(a: 0, b: 2, c: -3, d: 0, tx: 100, ty: 200)
        let plain = try document([stroke(100)]).raw.strokes[0]
        let moved = try document([stroke(100, transform: transform)]).raw.strokes[0]
        try check(plain.id == moved.id, "Stable identity after transform")
        for point in moved.points {
            let actual = moved.transform.apply(x: point.x, y: point.y)
            let expected = CGPoint(x: point.x, y: point.y).applying(transform)
            try check(actual.0 == expected.x && actual.1 == expected.y, "Affine coordinate fidelity")
        }
        try check(moved.points[1].time == 0.125 && moved.points[0].pressure == 0.5, "Timing/pressure fidelity")
        print("PASS affine transforms, identity, timing and pressure")
        var doc = try document([stroke(100), stroke(101), stroke(102)])
        let ids = doc.raw.strokes.map(\.id)
        let group = LabGroup(label: "Expression", strokeIDs: ids)
        doc.annotations.groups = [group]
        doc.annotations.record("Create expression", author: "test")
        try doc.annotations.split([ids[0]], from: group.id, author: "test")
        try check(doc.annotations.groups.count == 2, "Split")
        try doc.annotations.merge(Set(doc.annotations.groups.map(\.id)), author: "test")
        try check(Set(doc.annotations.groups[0].strokeIDs) == Set(ids), "Merge")
        doc.annotations.assign([ids[1]], to: nil, author: "test")
        try LabValidation.validate(raw: doc.raw, annotations: doc.annotations)
        doc.annotations.reconcile(existing: [], author: "test")
        try check(doc.annotations.groups[0].strokeIDs.isEmpty, "Erasure cleanup")
        let rewritten = try document([stroke(103)]).raw.strokes[0]
        try check(!ids.contains(rewritten.id), "Rewriting creates identity")
        print("PASS splitting, merging, unassignment, erasure cleanup and rewrite identity")
        let duplicate = try document([stroke(100), stroke(100)])
        try rejects("duplicate stroke identity") { _ = try duplicate.wrapper() }
        var invalid = try document([stroke(100)])
        invalid.annotations.groups = [LabGroup(label: "Invalid", strokeIDs: ["missing"])]
        try rejects("dangling membership") { try invalid.validate() }
        invalid.annotations.groups = []
        invalid.raw.strokes[0].points[1].time = -1
        try rejects("negative time") { try invalid.validate() }
        let valid = try document([stroke(100)])
        let wrapper = try valid.wrapper()
        wrapper.removeFileWrapper(wrapper.fileWrappers!["drawing.pkdrawing"]!)
        wrapper.addRegularFile(withContents: PKDrawing().dataRepresentation(), preferredFilename: "drawing.pkdrawing")
        try rejects("mismatched native ink") { _ = try StrokeLabDocument(wrapper: wrapper) }
        print("PASS invalid identities, membership, timing and mismatched native ink rejected")
        // Optionally retain a synthetic export outside the repository for the Python CLI.
        if CommandLine.arguments.count > 1 {
            try valid.wrapper().write(to: URL(fileURLWithPath: CommandLine.arguments[1]), options: .atomic, originalContentsURL: nil)
        }
        print("All Stroke Lab macOS smoke checks passed")
    }
}
