import Foundation

/// The urgency level of a task.
///
/// Raw `Int` values allow the enum to be stored directly in SwiftData
/// without a custom transformer. `Codable` conformance enables JSON
/// serialisation if tasks are ever exported or synced via a remote API.
/// `CaseIterable` is used to populate the segmented picker in `TaskEditView`.
enum Priority: Int, Codable, CaseIterable {
    /// No urgency assigned. The default value for new tasks.
    case none = 0
    /// Low urgency. Shown as a blue badge.
    case low = 1
    /// Moderate urgency. Shown as an orange badge.
    case medium = 2
    /// High urgency. Shown as a red badge.
    case high = 3

    /// The human-readable label shown in badges and picker controls.
    var label: String {
        switch self {
        case .none:   return "None"
        case .low:    return "Low"
        case .medium: return "Medium"
        case .high:   return "High"
        }
    }
}
