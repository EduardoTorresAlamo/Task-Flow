import SwiftUI
import EventKit
import Observation

enum TimelineEntry: Identifiable {
    case task(Task)
    case event(EKEvent)

    var id: String {
        switch self {
        case .task(let t): return t.id.uuidString
        case .event(let e): return e.eventIdentifier ?? UUID().uuidString
        }
    }

    var date: Date? {
        switch self {
        case .task(let t): return t.dueDate
        case .event(let e): return e.startDate
        }
    }
}

@Observable @MainActor final class TimelineViewModel {
    var calendarEvents: [EKEvent] = []

    func loadEvents(from service: EventKitService) {
        guard service.calendarAuthorized else { return }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 7, to: now) ?? now
        calendarEvents = service.fetchEvents(from: now, to: end)
    }

    func mergedEntries(tasks: [Task]) -> [TimelineEntry] {
        let taskEntries = tasks.compactMap { $0.dueDate != nil ? TimelineEntry.task($0) : nil }
        let eventEntries = calendarEvents.map { TimelineEntry.event($0) }
        return (taskEntries + eventEntries).sorted {
            ($0.date ?? .distantFuture) < ($1.date ?? .distantFuture)
        }
    }
}
