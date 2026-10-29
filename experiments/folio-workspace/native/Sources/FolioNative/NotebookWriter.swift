import Foundation
import FolioCore

/// Serial, off-main persistence. Older queued snapshots cannot replace newer ones.
actor NotebookWriter {
    private var newestGeneration = -1
    func write(_ document: InkDocument, to url: URL, generation: Int) throws {
        guard generation > newestGeneration else { return }
        let data = try document.encoded()
        try data.write(to: url, options: .atomic)
        newestGeneration = generation
    }
}
