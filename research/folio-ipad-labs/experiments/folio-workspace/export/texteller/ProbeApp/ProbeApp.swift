import SwiftUI
import CoreML
import Darwin

struct Fixture: Codable, Identifiable, Sendable {
    let id: String
    let image: String
    let tensor: String
    let groundTruth: String
    let referenceLatex: String
    let tokens: [Int]
}

struct FixtureManifest: Codable, Sendable {
    let revision: String
    let adapter: String
    let fixtures: [Fixture]
}

struct TokenizerTable: Decodable {
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
            guard pieces.indices.contains(token) else { throw ProbeError.invalid("Unknown token ID") }
            for scalar in pieces[token].unicodeScalars {
                guard let byte = byte_decoder[String(scalar.value)] else {
                    throw ProbeError.invalid("Unknown byte-level BPE character")
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

enum ProbeError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

struct ProbeResult: Codable, Identifiable, Sendable {
    let id: String
    let latex: String
    let tokens: [Int]
    let tokenParity: Bool
    let textParity: Bool
    let seconds: [Double]
    let sampledPeakFootprintBytes: UInt64
}

struct LocalRecognition: Codable, Sendable {
    let latex: String
    let tokens: [Int]
    let inferenceSeconds: Double
    let encoderSeconds: Double
    let decoderSeconds: Double
    let sampledPeakFootprintBytes: UInt64
}

/// All model execution stays on this actor, outside the SwiftUI main actor.
actor ModelRuntime {
    private var encoder: MLModel?
    private var decoder: MLModel?
    private var tokenizer: TokenizerTable?
    private(set) var loadSeconds = 0.0

    func load() throws {
        guard encoder == nil else { return }
        let started = ProcessInfo.processInfo.systemUptime
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndGPU
        guard let encoderURL = Bundle.main.url(forResource: "Encoder", withExtension: "mlmodelc"),
              let decoderURL = Bundle.main.url(forResource: "Decoder", withExtension: "mlmodelc"),
              let tableURL = Bundle.main.url(forResource: "tokenizer-table", withExtension: "json", subdirectory: "Fixtures") else {
            throw ProbeError.invalid("Missing bundled models or tokenizer. Run prepare_app.py first.")
        }
        let loadedEncoder = try MLModel(contentsOf: encoderURL, configuration: configuration)
        let loadedDecoder = try MLModel(contentsOf: decoderURL, configuration: configuration)
        let loadedTokenizer = try JSONDecoder().decode(TokenizerTable.self, from: Data(contentsOf: tableURL))
        for model in [loadedEncoder, loadedDecoder] {
            let metadata = model.modelDescription.metadata[.creatorDefinedKey] as? [String: String]
            guard metadata?["base_revision"] == "7b96df06b9d81cdb129c3bef68b7250bc3e2b0ea" else {
                throw ProbeError.invalid("Unexpected model revision")
            }
        }
        encoder = loadedEncoder; decoder = loadedDecoder; tokenizer = loadedTokenizer
        loadSeconds = ProcessInfo.processInfo.systemUptime - started
    }

    func recognize(_ values: [Float]) throws -> LocalRecognition {
        try Task.checkCancellation()
        try load()
        guard let encoder, let decoder, let tokenizer, values.count == 448 * 448,
              values.allSatisfy({ $0.isFinite }) else { throw ProbeError.invalid("Invalid recognition tensor") }
        let pixels = try MLMultiArray(shape: [1, 1, 448, 448], dataType: .float32)
        values.withUnsafeBytes { bytes in
            pixels.dataPointer.copyMemory(from: bytes.baseAddress!, byteCount: bytes.count)
        }
        let started = ProcessInfo.processInfo.systemUptime
        let output = try encoder.prediction(from: MLDictionaryFeatureProvider(dictionary: ["pixels": MLFeatureValue(multiArray: pixels)]))
        guard let encoded = output.featureValue(for: "encoded")?.multiArrayValue else {
            throw ProbeError.invalid("Encoder returned no features")
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
                  logits.strides.last?.intValue == 1 else { throw ProbeError.invalid("Unexpected decoder logits") }
            let scores = logits.dataPointer.assumingMemoryBound(to: Float.self)
            var best = 0
            for index in 0..<logits.count {
                guard scores[index].isFinite else { throw ProbeError.invalid("Non-finite logits") }
                if scores[index] > scores[best] { best = index }
            }
            ids.append(best); peak = max(peak, Self.footprint())
            if best == tokenizer.eos { break }
        }
        guard ids.last == tokenizer.eos else { throw ProbeError.invalid("Generation hit the token limit without EOS") }
        let finished = ProcessInfo.processInfo.systemUptime
        return LocalRecognition(latex: try tokenizer.decode(ids), tokens: ids,
            inferenceSeconds: finished - started, encoderSeconds: encodedAt - started,
            decoderSeconds: finished - encodedAt, sampledPeakFootprintBytes: peak)
    }

    func run(_ fixture: Fixture, trials: Int) throws -> ProbeResult {
        try load()
        guard let url = Bundle.main.url(forResource: fixture.id, withExtension: "f32", subdirectory: "Fixtures") else {
            throw ProbeError.invalid("Missing normalized fixture tensor")
        }
        let data = try Data(contentsOf: url)
        guard data.count == 448 * 448 * MemoryLayout<Float>.size else {
            throw ProbeError.invalid("Fixture tensor has the wrong byte length")
        }
        let values = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        var timings: [Double] = [], lastTokens: [Int] = [], parity = true
        var peak = Self.footprint()
        for _ in 0..<trials {
            let result = try recognize(values)
            timings.append(result.inferenceSeconds)
            parity = parity && result.tokens == fixture.tokens
            lastTokens = result.tokens
            peak = max(peak, result.sampledPeakFootprintBytes)
        }
        let latex = try tokenizer!.decode(lastTokens)
        return ProbeResult(id: fixture.id, latex: latex, tokens: lastTokens, tokenParity: parity,
                           textParity: latex == fixture.referenceLatex, seconds: timings,
                           sampledPeakFootprintBytes: peak)
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

@MainActor
final class ProbeViewModel: ObservableObject {
    @Published var fixtures: [Fixture] = []
    @Published var results: [ProbeResult] = []
    @Published var status = "Local model feasibility probe"
    @Published var busy = false
    private let runtime: ModelRuntime
    private var task: Task<Void, Never>?

    init(runtime: ModelRuntime) {
        self.runtime = runtime
        do {
            guard let url = Bundle.main.url(forResource: "probe-manifest", withExtension: "json", subdirectory: "Fixtures") else {
                throw ProbeError.invalid("Missing fixture manifest")
            }
            fixtures = try JSONDecoder().decode(FixtureManifest.self, from: Data(contentsOf: url)).fixtures
        } catch { status = error.localizedDescription }
    }

    func run() {
        guard !busy else { return }
        busy = true; results = []
        task = Task {
            defer { busy = false }
            do {
                guard fixtures.count == 6 else { throw ProbeError.invalid("The six fixture inputs are missing") }
                for fixture in fixtures {
                    status = "Reading \(fixture.id) locally…"
                    let result = try await runtime.run(fixture, trials: 3)
                    results.append(result)
                    let json = String(data: try JSONEncoder().encode(result), encoding: .utf8)!
                    print("FOLIO_PROBE_RESULT " + json)
                }
                let load = await runtime.loadSeconds
                let summary = DeviceReport(device: Self.hardware(), physicalDevice: Self.physical,
                    computeUnits: "CPU_AND_GPU", loadSeconds: load, results: results)
                let data = try JSONEncoder().encode(summary)
                let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("device-results.json")
                try data.write(to: url, options: .atomic)
                print("FOLIO_PROBE_SUMMARY " + String(data: data, encoding: .utf8)!)
                status = results.allSatisfy { $0.tokenParity && $0.textParity }
                    ? "All fixture token and text comparisons passed. Saved device-results.json."
                    : "Comparison differences found. Saved device-results.json."
                if ProcessInfo.processInfo.arguments.contains("--self-test") {
                    exit(results.allSatisfy { $0.tokenParity && $0.textParity } ? 0 : 2)
                }
            } catch {
                status = error.localizedDescription
                print("FOLIO_PROBE_ERROR " + error.localizedDescription)
                if ProcessInfo.processInfo.arguments.contains("--self-test") { exit(3) }
            }
        }
    }

    func cancel() { task?.cancel() }

    private struct DeviceReport: Codable {
        let device: String
        let physicalDevice: Bool
        let computeUnits: String
        let loadSeconds: Double
        let results: [ProbeResult]
    }

    private static var physical: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        true
        #endif
    }

    private static func hardware() -> String {
        var info = utsname(); uname(&info)
        let capacity = MemoryLayout.size(ofValue: info.machine)
        return withUnsafePointer(to: &info.machine) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
        }
    }
}

@main
struct TextellerProbeApp: App {
    @StateObject private var model: ProbeViewModel
    @StateObject private var pencil: PencilViewModel
    @State private var tab = ProcessInfo.processInfo.arguments.contains("--self-test") ? 1 : 0
    init() {
        let runtime = ModelRuntime()
        _model = StateObject(wrappedValue: ProbeViewModel(runtime: runtime))
        _pencil = StateObject(wrappedValue: PencilViewModel(runtime: runtime))
    }
    var body: some Scene {
        WindowGroup {
            TabView(selection: $tab) {
                NavigationStack { PencilRecognitionView(model: pencil).disabled(model.busy) }
                    .tabItem { Label("Write", systemImage: "pencil.tip") }.tag(0)
                    .task {
                        if ProcessInfo.processInfo.arguments.contains("--pencil-smoke-test") { await pencil.smokeTest() }
                    }
            NavigationStack {
                List {
                    Section {
                        Text("Synthetic fixtures → local Core ML → LaTeX")
                        Text("No server or network request. This measures conversion parity, not Apple Pencil accuracy.")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(model.status).textSelection(.enabled)
                        Button(model.busy ? "Running…" : "Run all six fixtures (3 trials each)") { model.run() }.disabled(model.busy)
                        if model.busy { Button("Cancel") { model.cancel() }; ProgressView() }
                    }
                    ForEach(model.fixtures) { fixture in
                        Section(fixture.id) {
                            if let url = Bundle.main.url(forResource: fixture.id, withExtension: "png", subdirectory: "Fixtures"),
                               let image = UIImage(contentsOfFile: url.path) {
                                Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 100)
                            }
                            Text("Ground truth: " + fixture.groundTruth).font(.system(.caption, design: .monospaced))
                            Text("PyTorch reference: " + fixture.referenceLatex).font(.system(.caption, design: .monospaced))
                            if let result = model.results.first(where: { $0.id == fixture.id }) {
                                Text(result.latex).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                                Text("Tokens: \(result.tokenParity ? "match" : "DIFFER"); text: \(result.textParity ? "match" : "DIFFER")")
                                Text("Seconds: " + result.seconds.map { String(format: "%.3f", $0) }.joined(separator: ", "))
                                Text("Sampled footprint: \(result.sampledPeakFootprintBytes / 1_048_576) MiB").font(.caption)
                            }
                        }
                    }
                }
                .navigationTitle("Folio ML Probe")
                .task { if ProcessInfo.processInfo.arguments.contains("--self-test") { model.run() } }
                .disabled(pencil.busy)
            }
            .tabItem { Label("Fixtures", systemImage: "checkmark.seal") }.tag(1)
            }
            .preferredColorScheme(.light)
        }
    }
}
