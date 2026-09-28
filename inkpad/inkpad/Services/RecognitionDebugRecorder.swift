import Foundation
import OSLog

#if DEBUG
struct RecognitionDebugContext: Sendable {
    let pageID: String
    let stepID: UUID
    let rowIndex: Int
    let minX: Double
    let minY: Double
    let width: Double
    let height: Double
    let strokeCount: Int
    let pointCount: Int
    let fingerprint: String
}

actor RecognitionDebugRecorder {
    static let shared = RecognitionDebugRecorder()

    private struct RowRecord: Codable {
        struct Bounds: Codable {
            let x: Double
            let y: Double
            let width: Double
            let height: Double
        }

        let timestamp: Date
        let pageID: String
        let stepID: UUID
        let rowIndex: Int
        let bounds: Bounds
        let strokeCount: Int
        let pointCount: Int
        let fingerprint: String
        let rawText: String
        let latex: String
        let confidence: Double
        let candidates: [RecognitionCandidate]
        let imageFilename: String?
        let durationMilliseconds: Int
    }

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "inkpad",
        category: "MathRecognition"
    )
    private let sessionDirectory: URL
    private let logURL: URL

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let root = documents.appendingPathComponent("InkPadDebug", isDirectory: true)
        sessionDirectory = root.appendingPathComponent("session-\(UUID().uuidString)", isDirectory: true)
        logURL = sessionDirectory.appendingPathComponent("rows.jsonl")
        logger.info("Recognition debug directory: \(self.sessionDirectory.path, privacy: .public)")
        logger.info("Recognition log file: \(self.logURL.path, privacy: .public)")
    }

    func record(context: RecognitionDebugContext, result: RecognitionResult) {
        do {
            try FileManager.default.createDirectory(
                at: sessionDirectory,
                withIntermediateDirectories: true
            )

            let imageFilename: String?
            if let png = result.debugImagePNG {
                let name = String(format: "row-%03d-%@.png", context.rowIndex, context.stepID.uuidString)
                try png.write(to: sessionDirectory.appendingPathComponent(name), options: .atomic)
                imageFilename = name
            } else {
                imageFilename = nil
            }

            let record = RowRecord(
                timestamp: Date(),
                pageID: context.pageID,
                stepID: context.stepID,
                rowIndex: context.rowIndex,
                bounds: .init(
                    x: context.minX,
                    y: context.minY,
                    width: context.width,
                    height: context.height
                ),
                strokeCount: context.strokeCount,
                pointCount: context.pointCount,
                fingerprint: context.fingerprint,
                rawText: result.text,
                latex: result.latex,
                confidence: result.confidence,
                candidates: result.candidates,
                imageFilename: imageFilename,
                durationMilliseconds: result.durationMilliseconds
            )
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var line = try encoder.encode(record)
            line.append(0x0A)
            if !FileManager.default.fileExists(atPath: logURL.path) {
                _ = FileManager.default.createFile(atPath: logURL.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: logURL)
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
            try handle.close()

            logger.info(
                "row=\(context.rowIndex) strokes=\(context.strokeCount) text=\(result.text, privacy: .public) latex=\(result.latex, privacy: .public) confidence=\(result.confidence) log=\(self.logURL.path, privacy: .public)"
            )
        } catch {
            logger.error("Could not write recognition debug record: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recordFailure(context: RecognitionDebugContext, error: Error) {
        logger.error(
            "row=\(context.rowIndex) strokes=\(context.strokeCount) recognition failed: \(error.localizedDescription, privacy: .public)"
        )
    }

    func currentLogURL() throws -> URL {
        try FileManager.default.createDirectory(
            at: sessionDirectory,
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: logURL.path) {
            _ = FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        logger.info("Sharing recognition log: \(self.logURL.path, privacy: .public)")
        return logURL
    }
}
#endif
