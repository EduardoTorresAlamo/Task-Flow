import Foundation
import Observation

/// Holds the task id delivered by a widget deep link so views can react to it.
///
/// `TaskFlowApp` injects this into the environment and updates
/// `pendingTaskID` from `.onOpenURL`. Any screen that wants to present the
/// tapped task can read `@Environment(DeepLinkCoordinator.self)` and observe
/// `pendingTaskID`, then clear it once handled.
///
/// - Note: This intentionally only *captures* the routed id. Wiring the id
///   through to a specific detail screen is left to the navigation layer so
///   the widget can be added without restructuring existing views.
@MainActor
@Observable
final class DeepLinkCoordinator {
    /// The most recent task id opened from a widget, or `nil` when none is pending.
    var pendingTaskID: UUID?

    /// Records a task id routed in from a `taskflow://task/<uuid>` URL.
    ///
    /// - Parameter id: The `Task.id` extracted by `TaskDeepLink.taskID(from:)`.
    func open(taskID id: UUID) {
        pendingTaskID = id
    }
}
