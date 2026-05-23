import Foundation
import SwiftData

/// A user-created task persisted via SwiftData.
///
/// `Task` is the core model in Task-Flow. It supports subtasks through a
/// self-referencing relationship, optional project grouping, free-form tags,
/// and an EventKit identifier that links the task to a calendar event.
///
/// - Note: `final` is required by SwiftData for `@Model` classes; the macro
///   synthesises `PersistentModel` conformance which relies on known-final dispatch.
@Model final class Task {
    /// Stable unique identifier. Defaults to a new UUID at creation.
    var id: UUID = UUID()

    /// The human-readable task title shown throughout the UI.
    var title: String

    /// Optional freeform text providing extra context for the task.
    var notes: String = ""

    /// The date and time by which the task should be completed.
    /// `nil` means the task has no time constraint.
    var dueDate: Date?

    /// Urgency level used for visual badging and NL parsing inference.
    var priority: Priority = Priority.none

    /// Whether the user has marked this task complete.
    var isCompleted: Bool = false

    /// Timestamp recorded the moment `isCompleted` flips to `true`.
    /// Cleared back to `nil` if the task is un-completed.
    var completedAt: Date?

    /// Timestamp recorded when the task was first inserted into the store.
    var createdAt: Date = Date()

    /// Timestamp updated whenever any property on this task changes.
    /// Used to order tasks and to drive EventKit re-sync on save.
    var updatedAt: Date = Date()

    /// The `EKEvent.eventIdentifier` of the calendar event that mirrors
    /// this task. `nil` when the task has not yet been synced to EventKit,
    /// or when the user has not granted calendar access.
    var eventKitIdentifier: String?

    /// The project this task belongs to, if any.
    ///
    /// `deleteRule: .nullify` means deleting a `Project` orphans the task
    /// rather than cascade-deleting it, preserving user data.
    @Relationship(deleteRule: .nullify) var project: Project?

    /// Child tasks nested beneath this one.
    ///
    /// `deleteRule: .cascade` ensures that deleting a parent task also
    /// removes all of its subtasks from the store, preventing orphan rows.
    @Relationship(deleteRule: .cascade) var subtasks: [Task] = []

    /// The parent task when this instance is itself a subtask.
    /// `nil` for top-level tasks.
    var parentTask: Task?

    /// Labels attached to this task for cross-cutting categorisation.
    @Relationship var tags: [Tag] = []

    /// Creates a new task with the given title and optional metadata.
    ///
    /// - Parameters:
    ///   - title: The required display name for the task.
    ///   - dueDate: An optional deadline. Pass `nil` for tasks with no time constraint.
    ///   - priority: The urgency level; defaults to `.none`.
    ///   - notes: Optional freeform notes; defaults to an empty string.
    init(
        title: String,
        dueDate: Date? = nil,
        priority: Priority = .none,
        notes: String = ""
    ) {
        self.title = title
        self.dueDate = dueDate
        self.priority = priority
        self.notes = notes
    }
}
