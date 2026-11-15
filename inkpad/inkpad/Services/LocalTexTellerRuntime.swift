import Foundation
import CoreML
import ImageIO
import Darwin

nonisolated struct TexTellerTokenizer: Decodable {
    let pieces: [String]
    let byte_decoder: [String: UInt8]
    let special_ids: [Int]
    let bos: Int
    let eos: Int
    let max_new_tokens: Int

    func decode(_ tokens: [Int]) throws -> String {
        let specials = Set(special_ids)
        var bytes: [UInt8] = []
        for token in tokens where !specials.contains(token) {
            guard pieces.indices.contains(token) else { throw LocalRecognitionError.invalid("Unknown token ID") }
            for scalar in pieces[token].unicodeScalars {
                guard let byte = byte_decoder[String(scalar.value)] else {
                    throw LocalRecognitionError.invalid("Unknown byte-level BPE character")
                }
                bytes.append(byte)
            }
        }
        var text = String(decoding: bytes, as: UTF8.self)
        for (before, after) in [(" .", "."), (" ?", "?"), (" !", "!"), (" ,", ","), (" ' ", "'"),
                                (" n't", "n't"), (" 'm", "'m"), (" 's", "'s"), (" 've", "'ve"), (" 're", "'re")] {
            text = text.replacingOccurrences(of: before, with: after)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var escaped = "", previous: Character?
        for character in text {
            if character == "%" && previous != "\\" { escaped.append("\\") }
            escaped.append(character); previous = character
        }
        for (opening, closing) in [("\\[", "\\]"), ("\\(", "\\)"), ("$$", "$$"), ("$", "$")] {
            if escaped.hasPrefix(opening) && escaped.hasSuffix(closing) {
                return String(escaped.dropFirst(opening.count).dropLast(closing.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return escaped
    }
}

nonisolated enum LocalRecognitionError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

nonisolated struct TexTellerPrediction: Codable, Sendable {
    let latex: String
    let tokens: [Int]
    let inferenceSeconds: Double
    let encoderSeconds: Double
    let decoderSeconds: Double
    let sampledPeakFootprintBytes: UInt64
}

actor LocalTexTellerRuntime {
    static let shared = LocalTexTellerRuntime()
    private var encoder: MLModel?
    private var decoder: MLModel?
    private var tokenizer: TexTellerTokenizer?
    private(set) var loadSeconds = 0.0

    func load() throws {
        guard encoder == nil else { return }
        let started = ProcessInfo.processInfo.systemUptime
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndGPU
        guard let encoderURL = Bundle.main.url(forResource: "Encoder", withExtension: "mlmodelc"),
              let decoderURL = Bundle.main.url(forResource: "Decoder", withExtension: "mlmodelc"),
              let tableURL = Bundle.main.url(forResource: "tokenizer-table", withExtension: "json") ?? Bundle.main.url(forResource: "tokenizer-table", withExtension: "json", subdirectory: "LocalTexTeller") else {
            throw LocalRecognitionError.invalid("The local math model is not bundled. Run scripts/prepare-local-recognition.py and rebuild, or select Mac recognition.")
        }
        let loadedEncoder = try MLModel(contentsOf: encoderURL, configuration: configuration)
        let loadedDecoder = try MLModel(contentsOf: decoderURL, configuration: configuration)
        let loadedTokenizer = try JSONDecoder().decode(TexTellerTokenizer.self, from: Data(contentsOf: tableURL))
        for model in [loadedEncoder, loadedDecoder] {
            let metadata = model.modelDescription.metadata[.creatorDefinedKey] as? [String: String]
            guard metadata?["base_revision"] == "7b96df06b9d81cdb129c3bef68b7250bc3e2b0ea" else {
                throw LocalRecognitionError.invalid("Unexpected model revision")
            }
        }
        encoder = loadedEncoder; decoder = loadedDecoder; tokenizer = loadedTokenizer
        loadSeconds = ProcessInfo.processInfo.systemUptime - started
    }

    func recognize(_ values: [Float]) throws -> TexTellerPrediction {
        try Task.checkCancellation()
        try load()
        guard let encoder, let decoder, let tokenizer, values.count == 448 * 448,
              values.allSatisfy({ $0.isFinite }) else { throw LocalRecognitionError.invalid("Invalid recognition tensor") }
        let pixels = try MLMultiArray(shape: [1, 1, 448, 448], dataType: .float32)
        values.withUnsafeBytes { bytes in
            pixels.dataPointer.copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
        }
        let started = ProcessInfo.processInfo.systemUptime
        let output = try encoder.prediction(from: MLDictionaryFeatureProvider(dictionary: ["pixels": MLFeatureValue(multiArray: pixels)]))
        guard let encoded = output.featureValue(for: "encoded")?.multiArrayValue else {
            throw LocalRecognitionError.invalid("Encoder returned no features")
        }
        let encodedAt = ProcessInfo.processInfo.systemUptime
        var ids = [tokenizer.bos], peak = Self.footprint()
        for _ in 0..<tokenizer.max_new_tokens {
            try Task.checkCancellation()
            let tokens = try MLMultiArray(shape: [1, NSNumber(value: ids.count)], dataType: .int32)
            let pointer = tokens.dataPointer.assumingMemoryBound(to: Int32.self)
            for (index, token) in ids.enumerated() { pointer[index] = Int32(token) }
            let inputs = try MLDictionaryFeatureProvider(dictionary: [
                "tokens": MLFeatureValue(multiArray: tokens), "encoded": MLFeatureValue(multiArray: encoded)])
            let prediction = try decoder.prediction(from: inputs)
            guard let logits = prediction.featureValue(for: "logits")?.multiArrayValue,
                  logits.dataType == .float32, logits.count == 15_000,
                  logits.strides.last?.intValue == 1 else { throw LocalRecognitionError.invalid("Unexpected decoder logits") }
            let scores = logits.dataPointer.assumingMemoryBound(to: Float.self)
            var best = 0
            for index in 0..<logits.count {
                guard scores[index].isFinite else { throw LocalRecognitionError.invalid("Non-finite logits") }
                if scores[index] > scores[best] { best = index }
            }
            ids.append(best); peak = max(peak, Self.footprint())
            if best == tokenizer.eos { break }
        }
        guard ids.last == tokenizer.eos else { throw LocalRecognitionError.invalid("Generation hit the token limit without EOS") }
        let finished = ProcessInfo.processInfo.systemUptime
        return TexTellerPrediction(latex: try tokenizer.decode(ids), tokens: ids,
            inferenceSeconds: finished - started, encoderSeconds: encodedAt - started,
            decoderSeconds: finished - encodedAt, sampledPeakFootprintBytes: peak)
    }

    func recognizePNG(_ png: Data) throws -> TexTellerPrediction {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(png as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw LocalRecognitionError.invalid("Could not open the handwriting image")
        }
        return try recognize(ImagePreprocessor.prepare(image).values)
    }

    private static func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }
}

