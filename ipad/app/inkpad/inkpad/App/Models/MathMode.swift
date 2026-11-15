import Foundation

enum MathMode: String, Codable, CaseIterable, Identifiable {
    case linalg, calc, proof

    var id: String { rawValue }

    var label: String {
        switch self {
        case .linalg: "LINALG"
        case .calc: "CALC"
        case .proof: "PROOF"
        }
    }

    var next: MathMode {
        switch self {
        case .linalg: .calc
        case .calc: .proof
        case .proof: .linalg
        }
    }
}
