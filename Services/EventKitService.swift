import EventKit
import Observation

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

    /// `true` when the user has granted full access to Calendar events.
    var calendarAuthorized = false

    /// `true` when the user has granted full access to Reminders.
    var remindersAuthorized = false

    /// Requests full Calendar and Reminders access using the iOS 17+ async APIs.
    ///
    /// The older `requestAccess(to:completion:)` API is deprecated in iOS 17;
    /// `requestFullAccessToEvents` and `requestFullAccessToReminders` are the
    /// replacements and return a `Bool` directly rather than using a callback.
    ///
    /// On denial or error both flags are set to `false` so callers can safely
    /// gate all store operations behind the authorization booleans.
    func requestPermissions() async {
        do {
            calendarAuthorized = try await store.requestFullAccessToEvents()
            remindersAuthorized = try await store.requestFullAccessToReminders()
        } catch {
            // Permission denied or an entitlement error occurred.
            calendarAuthorized = false
            remindersAuthorized = false
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
        remindersAuthorized = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
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
