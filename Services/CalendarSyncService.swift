import EventKit
import Observation

/// Handles the read/write of individual `EKEvent` records that mirror
/// Task-Flow tasks in the system Calendar.
///
/// This service is intentionally narrow: it knows how to upsert a single task
/// into EventKit and how to remove that event. Orchestration (batching,
/// authorization gating, state tracking) is the responsibility of `CalendarManager`.
///
/// Confined to `@MainActor` because it reads from `Task` objects, which are
/// SwiftData `@Model` instances that must not be accessed off the main actor.
/// The *blocking* store I/O is not done here: task fields are snapshotted into a
/// Sendable ``EventDraft`` on the main actor and the actual save/remove is
/// performed off the main thread by ``EventKitWriter``, so a slow synchronous
/// call to `calaccessd` never stalls the UI.
@Observable @MainActor final class CalendarSyncService {
    /// The EventKit facade used to reach authorization state and the background writer.
    private let eventKitService: EventKitService

    /// Extracts structured metadata (location, attendees, URL, duration)
    /// from a task's text content using NaturalLanguage APIs.
    private let enricher = IntelligenceEnricher()

    /// Creates a sync service backed by the given EventKit wrapper.
    ///
    /// - Parameter eventKitService: The shared service that owns `EKEventStore`.
    init(eventKitService: EventKitService) {
        self.eventKitService = eventKitService
    }

    /// Creates or updates the `EKEvent` that corresponds to the given task.
    ///
    /// The task fields — and the natural-language enrichment that reads them —
    /// are gathered on the main actor into a Sendable ``EventDraft``. The
    /// blocking store write is then performed off the main thread by
    /// ``EventKitWriter``. On a successful save `task.eventKitIdentifier` is set
    /// to the event's stable identifier so future calls upsert the same event.
    ///
    /// - Parameter task: The task whose calendar mirror should be created or updated.
    func sync(task: Task) async {
        guard eventKitService.calendarAuthorized else { return }

        // Snapshot everything the write needs while on the main actor, where the
        // SwiftData model is safe to touch. `EventDraft` is Sendable, so it can
        // cross to the writer actor; `EKEvent`/`EKEventStore` never do.
        let enriched = enricher.enrich(task: task)
        let start = task.dueDate ?? Date()
        let draft = EventDraft(
            existingIdentifier: task.eventKitIdentifier,
            calendarIdentifier: UserDefaults.standard.string(forKey: CalendarManager.selectedCalendarDefaultsKey),
            title: task.title,
            startDate: start,
            // Duration is derived from natural-language hints ("30 min", "2 hours"),
            // falling back to 3600 seconds (1 hour) when no hint is found.
            endDate: start.addingTimeInterval(enriched.durationSeconds),
            notes: enriched.formattedNotes.isEmpty ? nil : enriched.formattedNotes,
            location: enriched.location,
            url: enriched.url
        )

        if let savedIdentifier = await eventKitService.writer.upsert(draft) {
            // Persist the stable identifier so we can re-find this event later.
            // On failure the identifier is unchanged so the next sync retries.
            task.eventKitIdentifier = savedIdentifier
        }
    }

    /// Removes the `EKEvent` linked to the given task from the system Calendar.
    ///
    /// A no-op if the task has no `eventKitIdentifier`. The removal itself runs
    /// off the main thread via ``EventKitWriter``. On a successful removal
    /// `task.eventKitIdentifier` is set to `nil`; a missing or failed removal
    /// leaves it in place so a later attempt can retry.
    ///
    /// - Parameter task: The task whose calendar event should be deleted.
    func deleteEvent(for task: Task) async {
        guard eventKitService.calendarAuthorized,
              let identifier = task.eventKitIdentifier
        else { return }

        if await eventKitService.writer.remove(identifier: identifier) {
            task.eventKitIdentifier = nil
        }
    }
}
