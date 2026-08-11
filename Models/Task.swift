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
    /// B-tree index on the EventKit link so sync lookups by identifier do not
    /// scan the whole task table. See `eventKitIdentifier` for why it is not unique.
    #Index<Task>([\.eventKitIdentifier])

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
    ///
    /// Indexed via the `#Index` macro below because it is the lookup key for
    /// every sync round-trip: `CalendarSyncService` and `importCalendarEvents`
    /// fetch by this value to find the task already linked to an event, and
    /// without an index each such fetch is a full-table scan. Not `.unique` —
    /// several tasks legitimately carry `nil` before their first sync, and a
    /// unique constraint treats multiple nils as a collision.
    var eventKitIdentifier: String?

    /// The recurrence specification for this task, or `nil` for a one-off task.
    ///
    /// Stored as a single `Codable` SwiftData attribute. When set, completing
    /// the task spawns the next occurrence via `makeNextOccurrence(calendar:)`.
    var recurrenceRule: RecurrenceRule?

    /// An optional hard cutoff for the recurrence, mirrored from the rule's
    /// `endDate` at save time. Occurrences whose due date falls after this are
    /// never generated. `nil` means the recurrence has no task-level cutoff.
    var recurrenceEnd: Date?

    /// The 1-based index of this task within its recurrence series.
    ///
    /// The original task is occurrence 1; each generated successor increments
    /// the count. Used to enforce `RecurrenceRule.maxOccurrences`.
    var recurrenceCount: Int = 1

    /// The `id` of the successor occurrence this task spawned when it was
    /// completed, or `nil` if it has spawned none.
    ///
    /// Completing a recurring task inserts its next occurrence. Without a link
    /// back to that occurrence, un-completing the task cleared its own flags but
    /// left the spawned occurrence in the store, so one recurring task became
    /// two. Tracking the successor's id lets `InboxViewModel` remove exactly the
    /// occurrence a completion created when that completion is undone.
    var spawnedSuccessorID: UUID?

    /// The project this task belongs to, if any.
    ///
    /// `deleteRule: .nullify` means deleting a `Project` orphans the task
    /// rather than cascade-deleting it, preserving user data.
    @Relationship(deleteRule: .nullify) var project: Project?

    /// Child tasks nested beneath this one.
    ///
    /// `deleteRule: .cascade` ensures that deleting a parent task also
    /// removes all of its subtasks from the store, preventing orphan rows.
    ///
    /// `inverse: \Task.parentTask` pairs this collection with the
    /// `parentTask` back-reference so SwiftData maintains a single
    /// bidirectional relationship. Without the explicit inverse the macro
    /// can infer two unrelated one-way links, which corrupts the graph
    /// (a subtask appearing under the wrong parent, or cascade deletes
    /// firing on the wrong rows).
    @Relationship(deleteRule: .cascade, inverse: \Task.parentTask) var subtasks: [Task] = []

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

    /// Whether this task repeats on a schedule.
    var isRecurring: Bool { recurrenceRule != nil }

    /// Builds the next occurrence of a recurring task, carrying forward its
    /// metadata and recurrence configuration, or `nil` if the series has ended.
    ///
    /// The series ends when any of the following holds:
    /// - the task has no `recurrenceRule` or no `dueDate` to advance from;
    /// - the `maxOccurrences` cap has been reached;
    /// - the computed next due date falls after the rule's `endDate` or the
    ///   task's `recurrenceEnd` cutoff.
    ///
    /// Subtasks are intentionally not copied: each occurrence starts fresh.
    ///
    /// - Parameter calendar: The calendar used for date arithmetic; defaults to `.current`.
    /// - Returns: A new, unsaved `Task` for the next occurrence, or `nil` if the
    ///   recurrence has ended. The caller is responsible for inserting it into a context.
    func makeNextOccurrence(calendar: Calendar = .current) -> Task? {
        guard let rule = recurrenceRule, let base = dueDate else { return nil }
        // Enforce the occurrence cap, counting the original as occurrence 1.
        if let maxOccurrences = rule.maxOccurrences, recurrenceCount >= maxOccurrences { return nil }
        guard let nextDue = rule.nextDate(after: base, calendar: calendar) else { return nil }
        // Respect the task-level cutoff in addition to the rule's own endDate.
        if let recurrenceEnd, nextDue > recurrenceEnd { return nil }

        let next = Task(title: title, dueDate: nextDue, priority: priority, notes: notes)
        next.project = project
        next.tags = tags
        next.recurrenceRule = rule
        next.recurrenceEnd = recurrenceEnd
        next.recurrenceCount = recurrenceCount + 1
        return next
    }
}
