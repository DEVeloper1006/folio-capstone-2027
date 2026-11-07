import Foundation

struct EditorState: Codable {
    let document: String
    let current: String
    let registers: [String: [String]]
    let metadata: [String: String]
    var modes: [MathMode]? = nil
    var preferences: EditorPreferences? = nil

    func validate() throws {
        let custom = modes ?? []
        guard (MathMode.builtinIDs + custom.map(\.id)).contains(current), custom.count <= 64,
              Set(custom.map(\.id)).count == custom.count,
              Set(custom.map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }).count == custom.count,
              document.utf8.count <= 4_000_000,
              registers.count <= 128, registers.allSatisfy({ $0.key.count == 1 && $0.value.count <= 1000 && $0.value.allSatisfy { $0.count <= 40 } }),
              ["title", "student", "course", "date"].allSatisfy({ metadata[$0] != nil }),
              metadata.values.allSatisfy({ $0.count <= 4000 }), (preferences?.model.count ?? 0) <= 200 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        for mode in custom { try mode.validate() }
    }
}

struct EditorPreferences: Codable {
    let automatic: Bool
    let model: String
}

struct WorkspaceStore {
    let url: URL

    func read() throws -> Data {
        let data = try Data(contentsOf: url)
        try JSONDecoder().decode(EditorState.self, from: data).validate()
        return data
    }

    func write(_ data: Data) throws {
        try JSONDecoder().decode(EditorState.self, from: data).validate()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    func recoveryCopy() throws -> URL {
        let copy = url.deletingLastPathComponent().appendingPathComponent("Recovery-\(UUID().uuidString).folio")
        try FileManager.default.copyItem(at: url, to: copy)
        return copy
    }
}
