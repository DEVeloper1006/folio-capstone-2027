import Foundation

@MainActor
enum RowComputationScope {
    /// A row sees its own history plus results created in this presentation.
    /// Free-form calculations see only their current presentation's results.
    static func results(on page:Page,source:Step?,sessionIDs:Set<UUID>)->[ComputationResult] {
        page.steps.flatMap(\.computationResults).filter {
            !$0.isRemoved && (sessionIDs.contains($0.stableID) || (source != nil && $0.source?.stableID==source?.stableID))
        }.sorted { $0.createdAt > $1.createdAt }
    }
}
