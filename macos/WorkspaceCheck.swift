import Foundation

@main
struct WorkspaceCheck {
    static func main() throws {
        let legacy = Data(#"{"document":"hello","current":"linalg","registers":{},"metadata":{"title":"T","student":"","course":"","date":""}}"#.utf8)
        let old = try JSONDecoder().decode(EditorState.self, from: legacy)
        try old.validate()
        precondition(old.modes == nil && old.preferences == nil)
        let macro = try ModeDraft.Binding(key: "s", label: "Square root", latex: #"\sqrt{#1}"#).materialize()
        precondition(macro.before == #"\sqrt{{"# && macro.after == "}}")
        for body in [#"\sqrt{x}"#, "#1+#1"] {
            var rejected = false
            do { _ = try ModeDraft.Binding(key: "s", label: "Invalid", latex: body).materialize() } catch { rejected = true }
            precondition(rejected, "A generated macro must have exactly one argument")
        }
        let bindings = ["a", "b", "c"].map { MathBinding(key: $0, label: "Editable notation", before: #"\sqrt{"#, after: "}") }
        let mode = MathMode(id: "test-notation", title: "Test notation", summary: "State contract validation.", bindings: bindings)
        let state = EditorState(document: "one\ntwo", current: mode.id, registers: [:], metadata: old.metadata,
                                modes: [mode], preferences: EditorPreferences(automatic: true, model: "local-model"))
        try state.validate()
        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(EditorState.self, from: encoded)
        try decoded.validate()
        precondition(decoded.document == state.document && decoded.modes == [mode] && decoded.current == mode.id && decoded.preferences?.automatic == true)
        for proposal in [
            MathProposal(kind: .step, latex: "2x = 4", explanation: "Missing delimiters", mode: "linalg"),
            MathProposal(kind: .hint, latex: "$x$", explanation: "Must not edit", mode: "linalg"),
            MathProposal(kind: .step, latex: "$x$", explanation: "Unknown mode", mode: "missing")
        ] {
            var rejected = false
            do { try proposal.validate(allowedModes: MathMode.builtinIDs) } catch { rejected = true }
            precondition(rejected, "Invalid proposal passed the native boundary")
        }
        for invalid in [
            EditorState(document: "", current: "missing", registers: [:], metadata: old.metadata),
            EditorState(document: "", current: mode.id, registers: [:], metadata: old.metadata, modes: [mode, mode]),
            EditorState(document: "", current: "linalg", registers: ["a": Array(repeating: "x", count: 1001)], metadata: old.metadata),
            EditorState(document: String(repeating: "x", count: 4_000_001), current: "linalg", registers: [:], metadata: old.metadata)
        ] {
            var rejected = false
            do { try invalid.validate() } catch { rejected = true }
            precondition(rejected, "Invalid state must not replace saved work")
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("folio-store-check-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        let store = WorkspaceStore(url: temporary.appendingPathComponent("workspace.folio"))
        try store.write(encoded)
        let firstRead = try store.read()
        precondition(firstRead == encoded)
        let corrupt = Data("unreadable workspace".utf8)
        var rejectedWrite = false
        do { try store.write(corrupt) } catch { rejectedWrite = true }
        precondition(rejectedWrite)
        let afterRejectedWrite = try store.read()
        precondition(afterRejectedWrite == encoded, "Invalid data replaced the saved workspace")
        try corrupt.write(to: store.url)
        let copy = try store.recoveryCopy()
        let recoveryData = try Data(contentsOf: copy)
        precondition(recoveryData == corrupt)
        try store.write(encoded)
        let restored = try store.read()
        let preservedRecovery = try Data(contentsOf: copy)
        precondition(restored == encoded)
        precondition(preservedRecovery == corrupt, "Recovery copy was changed")
        print("Legacy loading, custom mode round-trip, invalid-state rejection, disk writes, and recovery preservation passed")
    }
}
