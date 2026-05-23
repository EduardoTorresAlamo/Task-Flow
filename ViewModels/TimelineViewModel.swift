import SwiftUI
import EventKit
import Observation

/// A unified entry in the merged task + calendar timeline.
///
/// Wraps either a SwiftData `Task` or an `EKEvent` so both can be
/// displayed in the same sorted list without type erasure or AnyView.
enum TimelineEntry: Identifiable {
    /// A Task-Flow task with an optional due date.
    case task(Task)
    /// A system calendar event.
    case event(EKEvent)

    /// A stable string identifier used by `ForEach` for list diffing.
    ///
    /// For tasks, the UUID is always stable. For events, `eventIdentifier`
    /// is used when available; a fresh UUID is generated as a fallback for
    /// events that somehow lack an identifier (this should not occur in practice).
    var id: String {
        switch self {
        case .task(let t):  return t.id.uuidString
        case .event(let e): return e.eventIdentifier ?? UUID().uuidString
        }
    }

    /// The point in time used to sort this entry in the timeline.
    ///
    /// Returns `nil` for tasks without a due date. Entries with a `nil` date
    /// are sorted to the end of the list by `mergedEntries(tasks:)`.
    var date: Date? {
        switch self {
        case .task(let t):  return t.dueDate
        case .event(let e): return e.startDate
        }
    }
}

/// View model for the timeline screen that merges Task-Flow tasks with
/// calendar events into a single chronological feed.
///
/// Isolated to `@MainActor` because:
/// - `calendarEvents` is an `@Observable` state property mutated from UI callbacks.
/// - `EKEvent` objects returned by `EventKitService.fetchEvents` are owned by the
///   `EKEventStore` which lives on the main actor inside `EventKitService`.
@Observable @MainActor final class TimelineViewModel {
    /// Calendar events loaded from EventKit for the current 7-day window.
    var calendarEvents: [EKEvent] = []

    /// Fetches calendar events for the next 7 days and stores them in `calendarEvents`.
    ///
    /// Guards against calling `fetchEvents` when authorization has not been
    /// granted, which would trigger a precondition failure inside `EKEventStore`.
    ///
    /// - Parameter service: The EventKit service that owns the `EKEventStore`.
    func loadEvents(from service: EventKitService) {
        guard service.calendarAuthorized else { return }
        let now = Date()
        // A 7-day lookahead keeps the timeline focused on near-term commitments
        // without overwhelming the user with distant future events.
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        calendarEvents = service.fetchEvents(from: now, to: end)
    }

    /// Merges the given tasks with the loaded calendar events into a
    /// single chronologically sorted array.
    ///
    /// Tasks without a due date are excluded because they have no timeline position.
    /// Entries with a `nil` date (which should not occur after the filter) are
    /// sorted to the far future so they appear at the end of the list.
    ///
    /// - Parameter tasks: The full list of tasks from the SwiftData store.
    /// - Returns: A merged, sorted array of `TimelineEntry` values.
    func mergedEntries(tasks: [Task]) -> [TimelineEntry] {
        // Only tasks with a scheduled date have a meaningful timeline position.
        let taskEntries  = tasks.compactMap { $0.dueDate != nil ? TimelineEntry.task($0) : nil }
        let eventEntries = calendarEvents.map { TimelineEntry.event($0) }
        return (taskEntries + eventEntries).sorted {
            ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture)
        }
    }
}
