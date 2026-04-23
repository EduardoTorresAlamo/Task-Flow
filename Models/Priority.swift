import Foundation

enum Priority: Int, Codable, CaseIterable {
    case none = 0, low = 1, medium = 2, high = 3

    var label: String {
        switch self {
        case .none: return "None"
        case .low: return "Low"
        case .medium: return "Medium"
        case .high: return "High"
        }
    }
}
