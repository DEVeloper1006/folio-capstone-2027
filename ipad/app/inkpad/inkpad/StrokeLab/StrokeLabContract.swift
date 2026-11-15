import Foundation

nonisolated struct LabPoint: Codable, Equatable {
    var x: Double
    var y: Double
    var time: Double
    var pressure: Double?
    var azimuth: Double?
    var altitude: Double?
    var width: Double
    var height: Double
    var opacity: Double
}

nonisolated struct LabTransform: Codable, Equatable {
    var a: Double = 1
    var b: Double = 0
    var c: Double = 0
    var d: Double = 1
    var tx: Double = 0
    var ty: Double = 0
    func apply(x: Double, y: Double) -> (Double, Double) {
        (a * x + c * y + tx, b * x + d * y + ty)
    }
}

nonisolated struct LabBounds: Codable, Equatable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double
}

nonisolated struct LabInk: Codable, Equatable {
    var type: String
    var rgba: [Double]
}

nonisolated struct LabStroke: Codable, Equatable, Identifiable {
    var id: String
    var createdAt: Double
    var points: [LabPoint]
    var transform: LabTransform
    var bounds: LabBounds
    var ink: LabInk
    var randomSeed: UInt32
}

nonisolated struct LabRawPage: Codable, Equatable {
    var schemaVersion = "1.0.0"
    var pageID: String = UUID().uuidString
    var coordinateSystem = "pencilkit-points-top-left-y-down"
    var pointSpace = "stroke-local"
    var timeUnit = "seconds"
    var creationTimeEpoch = "unix"
    var identityStrategy = "sha256-path-v1"
    var canvasWidth: Double = 1024
    var canvasHeight: Double = 1366
    var strokes: [LabStroke] = []
}

nonisolated struct LabRow: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var label: String
    var parentRowID: String?
    var strokeIDs: [String]
}

nonisolated struct LabGroup: Codable, Equatable, Identifiable {
    var id: String = UUID().uuidString
    var label: String
    var strokeIDs: [String]
    var rows: [LabRow] = []
}

nonisolated struct LabRevision: Codable, Equatable {
    var number: Int
    var timestamp: Double
    var author: String
    var source: String
    var action: String
}

nonisolated struct LabAnnotations: Codable, Equatable {
    var schemaVersion = "1.0.0"
    var pageID: String
    var revision: Int = 0
    var groups: [LabGroup] = []
    var history: [LabRevision] = []

    mutating func record(_ action: String, author: String) {
        revision += 1
        history.append(LabRevision(number: revision, timestamp: Date().timeIntervalSince1970,
                                   author: author, source: "manual-stroke-lab", action: action))
    }

    mutating func assign(_ ids: Set<String>, to groupID: String?, author: String) {
        for i in groups.indices where groups[i].id != groupID {
            groups[i].strokeIDs.removeAll { ids.contains($0) }
            for r in groups[i].rows.indices { groups[i].rows[r].strokeIDs.removeAll { ids.contains($0) } }
        }
        if let index = groups.firstIndex(where: { $0.id == groupID }) {
            groups[index].strokeIDs += ids.subtracting(groups[index].strokeIDs).sorted()
        }
        record(groupID == nil ? "Unassign strokes" : "Assign strokes", author: author)
    }

    mutating func split(_ ids: Set<String>, from groupID: String, author: String) throws {
        guard let group = groups.first(where: { $0.id == groupID }), !ids.isEmpty,
              ids.isSubset(of: Set(group.strokeIDs)), ids.count < group.strokeIDs.count else {
            throw LabError.invalid("Split requires a proper nonempty subset of one group")
        }
        let newGroup = LabGroup(label: group.label + " split", strokeIDs: [])
        groups.append(newGroup)
        assign(ids, to: newGroup.id, author: author)
    }

    mutating func merge(_ groupIDs: Set<String>, author: String) throws {
        let chosen = groups.filter { groupIDs.contains($0.id) }
        guard chosen.count >= 2, chosen.count == groupIDs.count else {
            throw LabError.invalid("Select at least two existing groups")
        }
        var merged = chosen[0]
        merged.strokeIDs = chosen.flatMap(\.strokeIDs)
        merged.rows = chosen.flatMap(\.rows)
        groups.removeAll { groupIDs.contains($0.id) }
        groups.append(merged)
        record("Merge groups", author: author)
    }

    mutating func reconcile(existing: Set<String>, author: String) {
        let missing = Set(groups.flatMap(\.strokeIDs)).subtracting(existing)
        guard !missing.isEmpty else { return }
        assign(missing, to: nil, author: author)
    }
}

nonisolated enum LabError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

/// Cross-reference and semantic checks supplement schemas/stroke-lab-v1.schema.json.
nonisolated struct LabValidation {
    static func validate(raw: LabRawPage, annotations: LabAnnotations) throws {
        func require(_ value: Bool, _ message: String) throws {
            if !value { throw LabError.invalid(message) }
        }
        try require(raw.schemaVersion == "1.0.0" && annotations.schemaVersion == "1.0.0", "Unsupported schema version")
        try require(raw.pageID == annotations.pageID && !raw.pageID.isEmpty, "Page identity mismatch")
        try require(raw.coordinateSystem == "pencilkit-points-top-left-y-down" && raw.pointSpace == "stroke-local" && raw.timeUnit == "seconds" && raw.creationTimeEpoch == "unix" && raw.identityStrategy == "sha256-path-v1", "Unsupported coordinate, time, or identity convention")
        try require(raw.canvasWidth.isFinite && raw.canvasWidth > 0 && raw.canvasHeight.isFinite && raw.canvasHeight > 0, "Invalid canvas")
        let ids = Set(raw.strokes.map(\.id))
        try require(ids.count == raw.strokes.count && !ids.contains(""), "Duplicate or empty stroke identity")
        for stroke in raw.strokes {
            let t = stroke.transform, b = stroke.bounds
            try require(([t.a,t.b,t.c,t.d,t.tx,t.ty,b.x,b.y,b.width,b.height,stroke.createdAt] + stroke.ink.rgba).allSatisfy(\.isFinite), "Nonfinite stroke metadata")
            try require(b.width >= 0 && b.height >= 0 && stroke.ink.rgba.count == 4 && stroke.ink.rgba.allSatisfy { (0...1).contains($0) }, "Invalid ink or bounds")
            try require(!stroke.points.isEmpty, "Stroke has no points")
            var previous = -Double.infinity
            for p in stroke.points {
                try require(([p.x,p.y,p.time,p.width,p.height,p.opacity] + [p.pressure,p.azimuth,p.altitude].compactMap { $0 }).allSatisfy(\.isFinite), "Nonfinite point")
                try require(p.time >= 0 && p.time >= previous && p.width >= 0 && p.height >= 0 && (0...1).contains(p.opacity), "Invalid point timing or size")
                previous = p.time
            }
        }
        try require(Set(annotations.groups.map(\.id)).count == annotations.groups.count, "Duplicate group IDs")
        var assigned = Set<String>()
        var rowIDs = Set<String>()
        for group in annotations.groups {
            let members = Set(group.strokeIDs)
            try require(!group.id.isEmpty && members.count == group.strokeIDs.count && members.isSubset(of: ids), "Invalid group membership")
            try require(assigned.isDisjoint(with: members), "A stroke belongs to multiple expressions")
            assigned.formUnion(members)
            let rows = Dictionary(grouping: group.rows, by: \.id)
            for row in group.rows {
                try require(!row.id.isEmpty && rowIDs.insert(row.id).inserted, "Duplicate row ID")
                let rowMembers = Set(row.strokeIDs)
                try require(rowMembers.count == row.strokeIDs.count && rowMembers.isSubset(of: members), "Row references strokes outside its expression")
                var visited: Set<String> = [row.id]
                var parent = row.parentRowID
                while let parentID = parent {
                    guard visited.insert(parentID).inserted, let ancestor = rows[parentID]?.first else {
                        throw LabError.invalid("Cyclic or missing row parent")
                    }
                    try require(rowMembers.isSubset(of: Set(ancestor.strokeIDs)), "Nested row must be contained in ancestors")
                    parent = ancestor.parentRowID
                }
            }
        }
        try require(annotations.revision == annotations.history.count, "Invalid revision count")
        for (index, event) in annotations.history.enumerated() {
            try require(event.number == index + 1 && event.timestamp.isFinite && !event.author.isEmpty && event.source == "manual-stroke-lab", "Invalid annotation provenance")
        }
    }
}
