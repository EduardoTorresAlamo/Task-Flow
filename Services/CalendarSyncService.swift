import EventKit
import Observation

@Observable @MainActor final class CalendarSyncService {
    private let eventKitService: EventKitService
    private let enricher = IntelligenceEnricher()

    init(eventKitService: EventKitService) {
        self.eventKitService = eventKitService
    }

    func sync(task: Task) {
        guard eventKitService.calendarAuthorized else { return }
        let store = eventKitService.store

        let ekEvent: EKEvent
        if let identifier = task.eventKitIdentifier,
           let existing = store.event(withIdentifier: identifier) {
            ekEvent = existing
        } else {
            ekEvent = EKEvent(eventStore: store)
            ekEvent.calendar = store.defaultCalendarForNewEvents
        }

        ekEvent.title = task.title
        let enriched = enricher.enrich(task: task)
        let start = task.dueDate ?? Date()
        ekEvent.startDate = start
        ekEvent.endDate = start.addingTimeInterval(enriched.durationSeconds)
        ekEvent.notes = enriched.formattedNotes.isEmpty ? nil : enriched.formattedNotes
        ekEvent.location = enriched.location
        if let url = enriched.url { ekEvent.url = url }

        do {
            try store.save(ekEvent, span: .thisEvent)
            task.eventKitIdentifier = ekEvent.eventIdentifier
        } catch {
            // Save failed — eventKitIdentifier remains unchanged
        }
    }

    func deleteEvent(for task: Task) {
        guard eventKitService.calendarAuthorized,
              let identifier = task.eventKitIdentifier,
              let ekEvent = eventKitService.store.event(withIdentifier: identifier)
        else { return }

        do {
            try eventKitService.store.remove(ekEvent, span: .thisEvent)
            task.eventKitIdentifier = nil
        } catch {
            // Removal failed — identifier preserved so retry is possible
        }
    }
}
