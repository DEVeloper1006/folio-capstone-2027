import SwiftUI
import PencilKit
import CryptoKit
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

extension UTType {
    nonisolated static let folioInk = UTType(exportedAs: "com.folio.stroke-lab", conformingTo: .package)
}

nonisolated struct LabExport {
    private struct Identity: Encodable {
        let createdAt: Double
        let points: [LabPoint]
        let ink: LabInk
        let seed: UInt32
    }

    static func page(from drawing: PKDrawing, preserving page: LabRawPage) throws -> LabRawPage {
        var result = page
        result.strokes = try drawing.strokes.map { stroke in
            guard stroke.mask == nil else { throw LabError.invalid("Masked strokes require a future schema; use whole-stroke erasing") }
            let points = stroke.path.map { p in
                LabPoint(x: p.location.x, y: p.location.y, time: p.timeOffset,
                         pressure: p.force, azimuth: p.azimuth, altitude: p.altitude,
                         width: p.size.width, height: p.size.height, opacity: p.opacity)
            }
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            #if canImport(UIKit)
            guard stroke.ink.color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
                .getRed(&r, green: &g, blue: &b, alpha: &a) else { throw LabError.invalid("Ink cannot be represented as sRGB") }
            #else
            guard let color = stroke.ink.color.usingColorSpace(.sRGB) else { throw LabError.invalid("Ink cannot be represented as sRGB") }
            color.getRed(&r, green: &g, blue: &b, alpha: &a)
            #endif
            let ink = LabInk(type: stroke.ink.inkType.rawValue, rgba: [r,g,b,a].map(Double.init))
            let created = stroke.path.creationDate.timeIntervalSince1970
            let identity = Identity(createdAt: created, points: points, ink: ink, seed: stroke.randomSeed)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let digest = SHA256.hash(data: try encoder.encode(identity)).map { String(format: "%02x", $0) }.joined()
            let t = stroke.transform, bounds = stroke.renderBounds
            return LabStroke(id: "sha256-" + digest, createdAt: created, points: points,
                             transform: LabTransform(a: t.a, b: t.b, c: t.c, d: t.d, tx: t.tx, ty: t.ty),
                             bounds: LabBounds(x: bounds.minX, y: bounds.minY, width: bounds.width, height: bounds.height),
                             ink: ink, randomSeed: stroke.randomSeed)
        }
        return result
    }
}

nonisolated struct StrokeLabDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folioInk] }
    var drawing: PKDrawing
    var raw: LabRawPage
    var annotations: LabAnnotations

    init() {
        drawing = PKDrawing()
        raw = LabRawPage()
        annotations = LabAnnotations(pageID: raw.pageID)
    }

    init(configuration: ReadConfiguration) throws { try self.init(wrapper: configuration.file) }

    init(wrapper: FileWrapper) throws {
        func data(_ name: String) throws -> Data {
            guard let value = wrapper.fileWrappers?[name]?.regularFileContents else { throw LabError.invalid("Missing \(name)") }
            return value
        }
        drawing = try PKDrawing(data: data("drawing.pkdrawing"))
        raw = try JSONDecoder().decode(LabRawPage.self, from: data("strokes.json"))
        annotations = try JSONDecoder().decode(LabAnnotations.self, from: data("annotations.json"))
        try StrokeLabSchema.validate(raw: data("strokes.json"), annotations: data("annotations.json"))
        try validate()
    }

    func validate() throws {
        try LabValidation.validate(raw: raw, annotations: annotations)
        let reexported = try LabExport.page(from: drawing, preserving: raw)
        guard reexported == raw else { throw LabError.invalid("Native drawing and portable strokes disagree") }
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { try wrapper() }

    func wrapper() throws -> FileWrapper {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let rawData = try encoder.encode(raw)
        let annotationData = try encoder.encode(annotations)
        try StrokeLabSchema.validate(raw: rawData, annotations: annotationData)
        return FileWrapper(directoryWithFileWrappers: [
            "drawing.pkdrawing": FileWrapper(regularFileWithContents: drawing.dataRepresentation()),
            "strokes.json": FileWrapper(regularFileWithContents: rawData),
            "annotations.json": FileWrapper(regularFileWithContents: annotationData)
        ])
    }
}

nonisolated struct StrokeLabStore {
    var directory: URL
    init(directory: URL? = nil) throws {
        self.directory = try directory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("StrokeLab", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }
    func pages() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "folioink" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    func save(_ document: StrokeLabDocument) throws {
        let url = directory.appendingPathComponent(document.raw.pageID).appendingPathExtension("folioink")
        try document.wrapper().write(to: url, options: .atomic, originalContentsURL: nil)
    }
    func open(_ url: URL) throws -> StrokeLabDocument {
        // Read known members directly. FileWrapper(url:) may consult Launch Services,
        // which is unavailable in command-line validation and unnecessary for local storage.
        var members: [String: FileWrapper] = [:]
        for name in ["drawing.pkdrawing", "strokes.json", "annotations.json"] {
            members[name] = FileWrapper(regularFileWithContents: try Data(contentsOf: url.appendingPathComponent(name)))
        }
        return try StrokeLabDocument(wrapper: FileWrapper(directoryWithFileWrappers: members))
    }
}
