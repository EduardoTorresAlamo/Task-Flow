import EventKit
import Observation
import SwiftData

/// High-level coordinator for all calendar-related operations in Task-Flow.
///
/// `CalendarManager` orchestrates the full EventKit workflow: requesting
/// permissions, maintaining the list of available calendars, syncing individual
/// or batched tasks, removing stale events, importing external calendar events
/// into SwiftData, and detecting scheduling conflicts.
///
/// It delegates low-level `EKEvent` I/O to `CalendarSyncService` and raw store
/// access to `EventKitService`, keeping this class focused on policy and state.
///
/// Confined to `@MainActor` because:
/// - `Task` (SwiftData `@Model`) must not cross actor boundaries.
/// - `ModelContext` is not `Sendable`.
/// - Observable state properties must be mutated on the main actor for safe UI updates.
@MainActor
@Observable
final class CalendarManager {

    // MARK: - Nested Types

    /// Represents the current phase of a sync operation.
    enum SyncState {
        /// No sync has been attempted since the last state reset.
        case idle
        /// A sync is currently in progress.
        case syncing
        /// The most recent sync completed successfully at the associated timestamp.
        case done(lastSyncedAt: Date)
        /// The most recent sync failed with the given human-readable message.
        case error(message: String)
    }

    /// A pair representing a Task-Flow task that overlaps in time with an
    /// existing calendar event, surfaced for the user to resolve.
    struct ConflictPair: Identifiable {
        /// Stable identity for use as a SwiftUI list item.
        let id = UUID()
        /// The Task-Flow task involved in the conflict.
        let task: Task
        /// The calendar event that occupies an overlapping time window.
        let conflictingEvent: EKEvent
    }

    // MARK: - Dependencies

    /// Provides authorization status and raw `EKEventStore` access.
    private let eventKitService: EventKitService

    /// Performs single-event upsert and delete operations.
    private let syncService: CalendarSyncService

    // MARK: - Observable State

    /// The current phase of the most recent sync operation.
    var syncState: SyncState = .idle

    /// Calendars available in the user's EventKit store, sorted alphabetically.
    var availableCalendars: [EKCalendar] = []

    /// The identifier of the calendar the user has chosen for task events.
    ///
    /// Persisted to `UserDefaults` so the selection survives app restarts
    /// without requiring a separate storage model.
    var selectedCalendarIdentifier: String? {
        didSet {
            // Mirror the selection to UserDefaults immediately; no explicit save needed.
            UserDefaults.standard.set(selectedCalendarIdentifier, forKey: "selectedCalendarIdentifier")
        }
    }

    // MARK: - Computed Properties

    /// `true` when both Calendar and Reminders access have been granted.
    ///
    /// Derived from `EventKitService` rather than stored locally so it always
    /// reflects the current authorization status without a separate sync step.
    var isAuthorized: Bool {
        eventKitService.calendarAuthorized && eventKitService.remindersAuthorized
    }

    // MARK: - Initialiser

    /// Creates the manager, restores the previously selected calendar, and
    /// eagerly loads the calendar list if permissions are already granted.
    ///
    /// - Parameters:
    ///   - eventKitService: The shared EventKit service that owns `EKEventStore`.
    ///   - syncService: The service responsible for individual event upserts/deletes.
    init(eventKitService: EventKitService, syncService: CalendarSyncService) {
        self.eventKitService = eventKitService
        self.syncService = syncService
        // Restore persisted calendar selection so the user does not have to re-pick it.
        selectedCalendarIdentifier = UserDefaults.standard.string(forKey: "selectedCalendarIdentifier")
        // Populate the calendar list immediately if the user already authorized the app
        // in a previous session; avoids an empty picker on first render.
        if isAuthorized {
            refreshCalendars()
        }
    }

    // MARK: - Permission

    /// Requests Calendar and Reminders access from the OS and refreshes the
    /// calendar list once the user responds to the permission prompt.
    ///
    /// This is the entry point for the app's permission flow, called from
    /// `RootTabView.onAppear` so the prompt appears as early as possible.
    func requestAccess() async {
        // Delegates the actual permission request to EventKitService,
        // which owns the EKEventStore and updates calendarAuthorized / remindersAuthorized.
        await eventKitService.requestPermissions()
        refreshCalendars()
    }

    // MARK: - Private Helpers

    /// Reloads `availableCalendars` from the EventKit store.
    ///
    /// Called after any authorization change or when the user opens a calendar
    /// picker. Sorted alphabetically so the list is stable across reloads.
    private func refreshCalendars() {
        availableCalendars = eventKitService.store
            .calendars(for: EKEntityType.event)
            .sorted { $0.title < $1.title }
    }

    // MARK: - Sync

    /// Syncs a single task to the system Calendar.
    ///
    /// Sets `syncState` to `.syncing` while the operation runs, then to
    /// `.done` on success or `.error` if access was not granted.
    ///
    /// - Parameter task: The task to create or update in EventKit.
    func syncTask(_ task: Task) async {
        guard isAuthorized else {
            syncState = .error(message: "Calendar access not granted")
            return
        }
        syncState = .syncing
        syncService.sync(task: task)
        syncState = .done(lastSyncedAt: Date())
    }

    /// Syncs every eligible task to the system Calendar in a single pass.
    ///
    /// Only tasks with a `dueDate` that are not yet completed are considered
    /// eligible; tasks without a due date have no meaningful time slot in a calendar.
    ///
    /// - Parameter tasks: The full list of tasks to evaluate for syncing.
    func syncAllTasks(_ tasks: [Task]) async {
        guard isAuthorized else {
            syncState = .error(message: "Calendar access not granted")
            return
        }
        // Filter to tasks that have a scheduled time and are still actionable.
        let eligible = tasks.filter { $0.dueDate != nil && !$0.isCompleted }
        syncState = .syncing
        for task in eligible {
            syncService.sync(task: task)
        }
        syncState = .done(lastSyncedAt: Date())
    }

    /// Removes the calendar event associated with the given task.
    ///
    /// A no-op if the task was never synced or the event was already deleted externally.
    ///
    /// - Parameter task: The task whose linked calendar event should be removed.
    func removeSync(for task: Task) async {
        syncService.deleteEvent(for: task)
    }

    // MARK: - Import

    /// Imports calendar events from the system Calendar into SwiftData as new `Task` objects.
    ///
    /// Only events that do not already have a matching task (identified by
    /// `eventKitIdentifier`) are imported, preventing duplicates on repeat calls.
    ///
    /// - Parameters:
    ///   - startDate: The beginning of the date range to search for events.
    ///   - endDate: The end of the date range to search for events.
    ///   - context: The SwiftData context into which new `Task` objects are inserted.
    /// - Returns: The count of newly created tasks.
    func importCalendarEvents(from startDate: Date, to endDate: Date, context: ModelContext) async -> Int {
        guard isAuthorized else { return 0 }
        let events = eventKitService.fetchEvents(from: startDate, to: endDate)
        var count = 0
        for event in events {
            guard let identifier = event.eventIdentifier else { continue }

            // Query SwiftData for a task already linked to this event identifier.
            // If one exists we skip the event to avoid creating a duplicate.
            let descriptor = FetchDescriptor<Task>(predicate: #Predicate { $0.eventKitIdentifier == identifier })
            let existing = (try? context.fetch(descriptor)) ?? []
            guard existing.isEmpty else { continue }

            let task = Task(
                title: event.title ?? "Untitled",
                dueDate: event.startDate,
                priority: .none,
                notes: event.notes ?? ""
            )
            task.eventKitIdentifier = identifier
            context.insert(task)
            count += 1
        }
        return count
    }

    // MARK: - Conflict Detection

    /// Returns all calendar events that overlap with the given task's due date
    /// within a +/- 30-minute window.
    ///
    /// Events that are already linked to the task itself (via `eventKitIdentifier`)
    /// are excluded from the results so the task's own mirror event is never
    /// reported as a conflict.
    ///
    /// - Parameter task: The task to check for scheduling conflicts.
    /// - Returns: An array of `ConflictPair` values, one per overlapping event.
    func detectConflicts(for task: Task) -> [ConflictPair] {
        guard let dueDate = task.dueDate, isAuthorized else { return [] }
        // Search a 60-minute window centered on the due date (30 min either side).
        let windowStart = dueDate.addingTimeInterval(-1800)
        let windowEnd   = dueDate.addingTimeInterval(1800)
        let events = eventKitService.fetchEvents(from: windowStart, to: windowEnd)
        return events
            // Exclude the task's own linked event so it does not conflict with itself.
            .filter { $0.eventIdentifier != task.eventKitIdentifier }
            .map { ConflictPair(task: task, conflictingEvent: $0) }
    }
}
