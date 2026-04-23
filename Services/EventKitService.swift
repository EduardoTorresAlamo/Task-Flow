import EventKit
import Observation

@Observable @MainActor final class EventKitService {
    let store = EKEventStore()
    var calendarAuthorized = false
    var remindersAuthorized = false

    func requestPermissions() async {
        do {
            calendarAuthorized = try await store.requestFullAccessToEvents()
            remindersAuthorized = try await store.requestFullAccessToReminders()
        } catch {
            calendarAuthorized = false
            remindersAuthorized = false
        }
    }

    func checkExistingAuthorization() {
        calendarAuthorized = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        remindersAuthorized = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    func fetchEvents(from start: Date, to end: Date) -> [EKEvent] {
        guard calendarAuthorized else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).sorted { $0.startDate < $1.startDate }
    }
}
