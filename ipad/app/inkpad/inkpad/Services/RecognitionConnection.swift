import Foundation
import SwiftUI

struct RecognitionConnection: Equatable {
    var provider: String = "local"
    var serverURL: String = ""
    var token: String = ""

    static func load() -> Self {
        let defaults = UserDefaults.standard
        return Self(provider: defaults.string(forKey: "recognition.provider") ?? "local",
                    serverURL: defaults.string(forKey: "recognition.serverURL") ?? "",
                    token: defaults.string(forKey: "recognition.token") ?? "")
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(provider, forKey: "recognition.provider")
        defaults.set(serverURL, forKey: "recognition.serverURL")
        defaults.set(token, forKey: "recognition.token")
    }

    func service() -> any RecognitionService {
        switch provider {
        case "local": LocalMathRecognitionService()
        case "mac": MacMathRecognitionService(connection: self)
        default: VisionMathRecognitionService()
        }
    }

    func baseURL() throws -> URL {
        guard let url = URL(string: serverURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme), let host = url.host, !host.isEmpty,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else {
            throw MacRecognitionError.message("Enter the Mac server URL, for example http://192.168.1.20:8002.")
        }
#if !DEBUG
        guard url.scheme == "https" else {
            throw MacRecognitionError.message("HTTP recognition is available only in development builds. Use HTTPS.")
        }
#endif
        guard !token.isEmpty else { throw MacRecognitionError.message("Enter the Mac connection token.") }
        return url
    }
}

enum MacRecognitionError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let text) = self { text } else { nil } }
}

struct MacMathRecognitionService: RecognitionService {
    let identifier = "mac"
    let connection: RecognitionConnection
    let session: URLSession

    init(connection: RecognitionConnection, session: URLSession = .shared) {
        self.connection = connection
        self.session = session
    }

    private func request(_ path: String) throws -> URLRequest {
        var request = URLRequest(url: try connection.baseURL().appendingPathComponent(path))
        request.timeoutInterval = 90
        request.setValue("Bearer " + connection.token, forHTTPHeaderField: "Authorization")
        return request
    }

    func health() async throws -> String {
        var healthRequest = try request("health")
        healthRequest.timeoutInterval = 5
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: healthRequest)
        } catch let error as URLError {
            switch error.code {
            case .timedOut, .cannotConnectToHost, .cannotFindHost, .notConnectedToInternet, .networkConnectionLost:
                throw MacRecognitionError.message("Cannot reach the Mac at \(connection.serverURL). Its Wi-Fi IP may have changed. Check the current server URL, keep both devices on the same Wi-Fi, and allow Ink Pad local-network access in Settings. You can also use the Mac's .local hostname.")
            default: throw error
            }
        }
        try check(response)
        struct Health: Decodable { let ready: Bool; let profile: String? }
        let health = try JSONDecoder().decode(Health.self, from: data)
        guard health.ready else { throw MacRecognitionError.message("The Mac model is still loading.") }
        return health.profile == "grade12" ? "TexTeller + Grade 12 adapter" : "TexTeller base"
    }

    func recognize(inkData: Data, mode: MathMode) async throws -> RecognitionResult {
        let started = Date()
        let png = try await MainActor.run { try RowInkRenderer.renderPNG(inkData: inkData) }
        guard png.count < 2_500_000 else { throw MacRecognitionError.message("This row is too large. Try a shorter expression.") }
        var request = try request("recognize")
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["image": "data:image/png;base64," + png.base64EncodedString(), "mode": "math"])
        for attempt in 0...3 {
            try Task.checkCancellation()
            let (data, response) = try await session.data(for: request)
            if (response as? HTTPURLResponse)?.statusCode == 503, attempt < 3 {
                try await Task.sleep(for: .seconds(attempt + 1))
                continue
            }
            try check(response)
            struct Reply: Decodable { let latex: String; let alternatives: [String]? }
            let reply = try JSONDecoder().decode(Reply.self, from: data)
            guard !reply.latex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  reply.latex.count <= 10_000 else {
                throw MacRecognitionError.message("The model returned no readable expression.")
            }
            return RecognitionResult(text: reply.latex, latex: reply.latex, confidence: nil,
                candidates: ([reply.latex] + (reply.alternatives ?? [])).reduce(into: [String]()) { result, value in
                    if !result.contains(value), value.count <= 10_000 { result.append(value) }
                }.prefix(3).map { RecognitionCandidate(text: $0, confidence: nil) },
                debugImagePNG: png, durationMilliseconds: Int(Date().timeIntervalSince(started) * 1000))
        }
        throw MacRecognitionError.message("The Mac recognizer is busy. Use Retry.")
    }

    private func check(_ response: URLResponse) throws {
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: return
        case 401: throw MacRecognitionError.message("The connection token is incorrect.")
        case 403: throw MacRecognitionError.message("The Mac server does not allow this hostname or IP.")
        case 413: throw MacRecognitionError.message("The row image is too large.")
        case 422: throw MacRecognitionError.message("The model could not read this row.")
        case 503: throw MacRecognitionError.message("The Mac recognizer is busy or unavailable. Use Retry.")
        default: throw MacRecognitionError.message("Could not connect to the Mac recognition service.")
        }
    }
}

struct RecognitionSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State var connection: RecognitionConnection
    let onSave: (RecognitionConnection) -> Void
    @State private var status = ""
    @State private var testing = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Recognition provider") {
                    Picker("Provider", selection: $connection.provider) {
                        Text("Local TexTeller (on iPad)").tag("local")
                        Text("Apple Vision baseline").tag("vision")
                        Text("Mac TexTeller").tag("mac")
                    }
                }
                if connection.provider == "local" {
                    Section("On-device recognition") {
                        Text("Runs the bundled TexTeller model on this iPad. No server address or token is needed. Recognition starts when you tap Recognize; the first request loads the model.")
                        Button(testing ? "Loading…" : "Check local model") {
                            testing = true
                            Task {
                                defer { testing = false }
                                do { try await LocalTexTellerRuntime.shared.load(); status = "Local model loaded." }
                                catch { status = error.localizedDescription }
                            }
                        }.disabled(testing)
                        if !status.isEmpty { Text(status).font(.caption).textSelection(.enabled) }
                    }
                }
                if connection.provider == "mac" {
                    Section("Mac connection") {
                        TextField("http://192.168.1.20:8002", text: $connection.serverURL)
                            .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        SecureField("Connection token", text: $connection.token)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        Text("Row images are sent to your Mac over your local network. Keep both devices on the same trusted Wi-Fi. HTTP is for development testing.")
                            .font(.caption)
                        Button(testing ? "Connecting…" : "Test connection") {
                            let snapshot = connection
                            testing = true
                            Task {
                                defer { testing = false }
                                do {
                                    let model = try await MacMathRecognitionService(connection: snapshot).health()
                                    if snapshot == connection { status = "Connected: " + model }
                                } catch {
                                    if snapshot == connection { status = error.localizedDescription }
                                }
                            }
                        }.disabled(testing)
                        if !status.isEmpty { Text(status).font(.caption).textSelection(.enabled) }
                    }
                }
            }
            .navigationTitle("Handwriting recognition")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { connection.save(); onSave(connection); dismiss() }.disabled(testing)
                }
            }
        }
    }
}
