import EventKit
import Observation
import SwiftData

@MainActor
@Observable
final class CalendarManager {

    enum SyncState {
        case idle
        case syncing
        case done(lastSyncedAt: Date)
        case error(message: String)
    }

    struct ConflictPair: Identifiable {
        let id = UUID()
        let task: Task
        let conflictingEvent: EKEvent
    }

    private let eventKitService: EventKitService
    private let syncService: CalendarSyncService

    var syncState: SyncState = .idle
    var availableCalendars: [EKCalendar] = []
    var selectedCalendarIdentifier: String? {
        didSet {
            UserDefaults.standard.set(selectedCalendarIdentifier, forKey: "selectedCalendarIdentifier")
        }
    }

    var isAuthorized: Bool {
        eventKitService.calendarAuthorized && eventKitService.remindersAuthorized
    }

    init(eventKitService: EventKitService, syncService: CalendarSyncService) {
        self.eventKitService = eventKitService
        self.syncService = syncService
        selectedCalendarIdentifier = UserDefaults.standard.string(forKey: "selectedCalendarIdentifier")
        if isAuthorized {
            refreshCalendars()
        }
    }

    func requestAccess() async {
        await eventKitService.requestPermissions()
        refreshCalendars()
    }

    private func refreshCalendars() {
        availableCalendars = eventKitService.store.calendars(for: EKEntityType.event).sorted { $0.title < $1.title }
    }

    func syncTask(_ task: Task) async {
        guard isAuthorized else {
            syncState = .error(message: "Calendar access not granted")
            return
        }
        syncState = .syncing
        syncService.sync(task: task)
        syncState = .done(lastSyncedAt: Date())
    }

    func syncAllTasks(_ tasks: [Task]) async {
        guard isAuthorized else {
            syncState = .error(message: "Calendar access not granted")
            return
        }
        let eligible = tasks.filter { $0.dueDate != nil && !$0.isCompleted }
        syncState = .syncing
        for task in eligible {
            syncService.sync(task: task)
        }
        syncState = .done(lastSyncedAt: Date())
    }

    func removeSync(for task: Task) async {
        syncService.deleteEvent(for: task)
    }

    func importCalendarEvents(from startDate: Date, to endDate: Date, context: ModelContext) async -> Int {
        guard isAuthorized else { return 0 }
        let events = eventKitService.fetchEvents(from: startDate, to: endDate)
        var count = 0
        for event in events {
            guard let identifier = event.eventIdentifier else { continue }
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

    func detectConflicts(for task: Task) -> [ConflictPair] {
        guard let dueDate = task.dueDate, isAuthorized else { return [] }
        let windowStart = dueDate.addingTimeInterval(-1800)
        let windowEnd = dueDate.addingTimeInterval(1800)
        let events = eventKitService.fetchEvents(from: windowStart, to: windowEnd)
        return events
            .filter { $0.eventIdentifier != task.eventKitIdentifier }
            .map { ConflictPair(task: task, conflictingEvent: $0) }
    }
}
