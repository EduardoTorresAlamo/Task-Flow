import EventKit
import Observation
import os.log

/// A `Sendable` snapshot of the calendar-event fields for one task.
///
/// Built on the main actor (where the SwiftData `Task` is safe to read) and
/// handed to ``EventKitWriter`` for the off-main-thread store write. Every field
/// is a value type, so the draft crosses the actor boundary without carrying an
/// `EKEvent`, which is not `Sendable`.
struct EventDraft: Sendable {
    /// The identifier of an existing event to update, or `nil` to create one.
    var existingIdentifier: String?
    /// The user's chosen calendar identifier, or `nil` to use the system default.
    var calendarIdentifier: String?
    var title: String
    var startDate: Date
    var endDate: Date
    var notes: String?
    var location: String?
    var url: URL?
}

/// Performs the blocking EventKit write path off the main thread.
///
/// `EKEventStore.save`/`remove` are synchronous IPC to `calaccessd`. Running
/// them from `@MainActor` (where `CalendarSyncService` lives, because it reads
/// SwiftData `Task` models) stalls the UI. This `actor` runs those writes on a
/// cooperative background thread instead.
///
/// It owns a second `EKEventStore` dedicated to writes: EventKit supports
/// multiple stores per process, and TCC authorization is process-wide, so the
/// user is never prompted twice. `EventKitService` still owns the main store
/// used for reads and authorization, and this file remains the only place an
/// `EKEventStore` is instantiated.
actor EventKitWriter {
    /// Background-confined store used only for the write path. It never leaves
    /// the actor, so its non-`Sendable` nature is contained.
    private let store = EKEventStore()

    /// Logs write failures by error *type* only — never a task's title, notes,
    /// or any other user content (see PRIVACY.md).
    private static let logger = Logger(subsystem: "com.eduardotorres.Task-Flow", category: "CalendarSync")

    /// Creates or updates the discrete calendar event described by `draft`.
    ///
    /// Recurrence is app-managed (see `CalendarSyncService`): no `EKRecurrenceRule`
    /// is authored and the event is saved with `.thisEvent`, which also leaves
    /// any rule already on an existing event intact.
    ///
    /// - Returns: The saved event's stable identifier, or `nil` if the save
    ///   failed (the caller then keeps the task's current identifier for a retry).
    func upsert(_ draft: EventDraft) -> String? {
        let ekEvent: EKEvent
        if let identifier = draft.existingIdentifier,
           let existing = store.event(withIdentifier: identifier) {
            ekEvent = existing
        } else {
            ekEvent = EKEvent(eventStore: store)
            ekEvent.calendar = targetCalendar(draft.calendarIdentifier)
        }

        ekEvent.title = draft.title
        ekEvent.startDate = draft.startDate
        ekEvent.endDate = draft.endDate
        ekEvent.notes = draft.notes
        ekEvent.location = draft.location
        if let url = draft.url { ekEvent.url = url }

        do {
            try store.save(ekEvent, span: .thisEvent)
            return ekEvent.eventIdentifier
        } catch {
            Self.logger.error("EKEventStore save failed: \(String(describing: type(of: error)), privacy: .public)")
            return nil
        }
    }

    /// Removes the event with the given identifier.
    ///
    /// - Returns: `true` only when an event was found and successfully removed.
    ///   A missing event (already deleted externally) or a failed remove returns
    ///   `false`, so the caller preserves the task's identifier.
    func remove(identifier: String) -> Bool {
        guard let ekEvent = store.event(withIdentifier: identifier) else { return false }
        do {
            try store.remove(ekEvent, span: .thisEvent)
            return true
        } catch {
            Self.logger.error("EKEventStore remove failed: \(String(describing: type(of: error)), privacy: .public)")
            return false
        }
    }

    /// The calendar a new event should land on: the user's picked calendar when
    /// it still resolves, otherwise the store's default for new events.
    private func targetCalendar(_ identifier: String?) -> EKCalendar? {
        if let identifier, let selected = store.calendar(withIdentifier: identifier) {
            return selected
        }
        return store.defaultCalendarForNewEvents
    }
}

/// The sole owner of `EKEventStore` in the application.
///
/// All EventKit reads and writes are funnelled through this service so that
/// exactly one store instance is alive at any time. `EKEventStore` is not
/// `Sendable`, so the class is confined to the `@MainActor` to satisfy
/// Swift 6 strict concurrency without data-race warnings.
///
/// - Note: `@Observable` replaces `ObservableObject`/`@Published` under the
///   Swift 6 observation model; SwiftUI views that read properties of this
///   service will automatically re-render when those properties change.
@Observable @MainActor final class EventKitService {
    /// The shared EventKit store. Created once and reused for the app lifetime.
    ///
    /// Only `EventKitService` should access this property directly. Other
    /// services receive it as a parameter so the store is never instantiated
    /// in more than one place.
    let store = EKEventStore()

    /// Performs blocking event upserts/deletes off the main thread. Owns its own
    /// background store; see ``EventKitWriter``.
    let writer = EventKitWriter()

    /// `true` when the user has granted full access to Calendar events.
    var calendarAuthorized = false

    /// Requests full Calendar access using the iOS 17+ async API.
    ///
    /// The older `requestAccess(to:completion:)` API is deprecated in iOS 17;
    /// `requestFullAccessToEvents` is the replacement and returns a `Bool`
    /// directly rather than using a callback.
    ///
    /// On denial or error the flag is set to `false` so callers can safely
    /// gate all store operations behind the authorization boolean.
    func requestPermissions() async {
        do {
            calendarAuthorized = try await store.requestFullAccessToEvents()
        } catch {
            // Calendar permission denied or an entitlement error occurred.
            calendarAuthorized = false
        }
    }

    /// Synchronously reads the current authorization status from EventKit without
    /// triggering a permission prompt.
    ///
    /// Call this at launch to restore the authorized state before the user
    /// interacts with any calendar-aware feature.
    func checkExistingAuthorization() {
        // .fullAccess is the iOS 17+ status that replaces the old .authorized value.
        calendarAuthorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Returns all calendar events that fall within the given date window, sorted by start date.
    ///
    /// Returns an empty array immediately when calendar access has not been granted,
    /// avoiding a precondition failure inside `EKEventStore.events(matching:)`.
    ///
    /// - Parameters:
    ///   - start: The beginning of the search window (inclusive).
    ///   - end: The end of the search window (exclusive).
    /// - Returns: Matching `EKEvent` objects sorted ascending by `startDate`.
    func fetchEvents(from start: Date, to end: Date) -> [EKEvent] {
        guard calendarAuthorized else { return [] }
        // NSPredicate-based search is the only bulk-fetch API EventKit exposes.
        // Passing nil for calendars searches across all calendars the user has access to.
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }
}
