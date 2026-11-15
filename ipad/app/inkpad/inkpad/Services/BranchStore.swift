import PencilKit

protocol BranchStore {
    func createBranch(name: String, from drawing: PKDrawing) -> Branch
    func branches() -> [Branch]
}

final class MockBranchStore: BranchStore {
    private var storedBranches: [Branch] = []

    func createBranch(name: String, from drawing: PKDrawing) -> Branch {
        let branch = Branch(name: name, sortIndex: storedBranches.count)
        branch.drawingData = drawing.dataRepresentation()
        storedBranches.append(branch)
        return branch
    }

    func branches() -> [Branch] {
        storedBranches
    }
}
