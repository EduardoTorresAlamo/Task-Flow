import EventKit
import Observation
import os.log

/// Handles the low-level read/write of individual `EKEvent` records
/// that mirror Task-Flow tasks in the system Calendar.
///
/// This service is intentionally narrow: it knows how to upsert a single
/// task into EventKit and how to remove that event. Orchestration (batching,
/// authorization gating, state tracking) is the responsibility of `CalendarManager`.
///
/// Confined to `@MainActor` because it reads from `Task` objects, which are
/// SwiftData `@Model` instances that must not be accessed off the main actor.
@Observable @MainActor final class CalendarSyncService {
    /// The EventKit facade used to access `EKEventStore`.
    private let eventKitService: EventKitService

    /// Logger for calendar-sync failures. Records error *types* only — never a
    /// task's title, notes, or any other user content (see PRIVACY.md).
    private static let logger = Logger(subsystem: "com.eduardotorres.Task-Flow", category: "CalendarSync")

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
    /// The method implements upsert semantics: if the task already has an
    /// `eventKitIdentifier` and that identifier resolves to an existing event,
    /// the existing event is updated in-place. Otherwise a new event is created
    /// on the user's default calendar.
    ///
    /// After a successful save, `task.eventKitIdentifier` is set to the event's
    /// stable identifier so future calls can find the same event.
    ///
    /// - Parameter task: The task whose calendar mirror should be created or updated.
    func sync(task: Task) {
        guard eventKitService.calendarAuthorized else { return }
        let store = eventKitService.store

        // Attempt to find an existing event before creating a new one.
        // `store.event(withIdentifier:)` returns nil if the event was deleted
        // externally, in which case we fall through to the creation path.
        let ekEvent: EKEvent
        if let identifier = task.eventKitIdentifier,
           let existing = store.event(withIdentifier: identifier) {
            ekEvent = existing
        } else {
            ekEvent = EKEvent(eventStore: store)
            ekEvent.calendar = Self.targetCalendar(in: store)
        }

        // Populate the event fields from the task and its enriched metadata.
        ekEvent.title = task.title
        let enriched = enricher.enrich(task: task)
        let start = task.dueDate ?? Date()
        ekEvent.startDate = start
        // Duration is derived from natural-language hints ("30 min", "2 hours").
        // Falls back to 3600 seconds (1 hour) when no duration hint is found.
        ekEvent.endDate = start.addingTimeInterval(enriched.durationSeconds)
        ekEvent.notes = enriched.formattedNotes.isEmpty ? nil : enriched.formattedNotes
        ekEvent.location = enriched.location
        if let url = enriched.url { ekEvent.url = url }

        // Recurrence is app-managed, never EventKit-managed.
        //
        // Task-Flow models a repeating task as a chain of discrete `Task` rows:
        // completing one spawns the next occurrence (see
        // `InboxViewModel.completeRecurring`), and each occurrence carries the
        // same `recurrenceRule`. Every occurrence therefore maps to exactly one
        // calendar event on its own due date.
        //
        // Authoring an `EKRecurrenceRule` here would make EventKit *also* expand
        // each occurrence into its own open-ended series saved with
        // `.futureEvents`. Because every spawned occurrence re-ran that path, N
        // completions produced N overlapping series — the recurring event
        // duplicated on every completion, growing without bound. We mirror
        // discrete occurrences only: no recurrence rule is written, and just
        // this event is saved with `.thisEvent`.
        //
        // Any rule already on the event (a series created before this change, or
        // one the user added in Calendar) is left untouched. Clearing it would
        // require a `.futureEvents` save that wipes the user's own rule, and
        // modifying `recurrenceRules` then saving `.thisEvent` throws; leaving it
        // alone edits only this occurrence and never throws.
        do {
            try store.save(ekEvent, span: .thisEvent)
            // Persist the stable identifier so we can re-find this event later.
            task.eventKitIdentifier = ekEvent.eventIdentifier
        } catch {
            // Save failed -- eventKitIdentifier remains unchanged so the next
            // sync retries. Log the error type (no user content) instead of
            // swallowing it silently, which previously hid write failures.
            Self.logger.error("EKEventStore save failed: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    /// Removes the `EKEvent` linked to the given task from the system Calendar.
    ///
    /// If the task has no `eventKitIdentifier`, or if the corresponding event
    /// cannot be found (e.g. it was deleted externally), the method returns
    /// without error. On successful removal, `task.eventKitIdentifier` is
    /// set to `nil` so the task is no longer considered synced.
    ///
    /// - Parameter task: The task whose calendar event should be deleted.
    func deleteEvent(for task: Task) {
        guard eventKitService.calendarAuthorized,
              let identifier = task.eventKitIdentifier,
              let ekEvent = eventKitService.store.event(withIdentifier: identifier)
        else { return }

        do {
            try eventKitService.store.remove(ekEvent, span: .thisEvent)
            task.eventKitIdentifier = nil
        } catch {
            // Removal failed -- identifier preserved so retry is possible. Log
            // the error type (no user content) rather than dropping it silently.
            Self.logger.error("EKEventStore remove failed: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    /// The calendar a new task event should be created on.
    ///
    /// Honours the user's picked calendar (persisted by `CalendarManager` under
    /// `selectedCalendarDefaultsKey`) when it still resolves to a real calendar,
    /// and otherwise falls back to the system default for new events. Previously
    /// the selection was ignored and every event landed on the default calendar.
    ///
    /// - Parameter store: The EventKit store to resolve the identifier against.
    /// - Returns: The chosen calendar, or the store's default when no valid
    ///   selection exists.
    private static func targetCalendar(in store: EKEventStore) -> EKCalendar? {
        if let identifier = UserDefaults.standard.string(forKey: CalendarManager.selectedCalendarDefaultsKey),
           let selected = store.calendar(withIdentifier: identifier) {
            return selected
        }
        return store.defaultCalendarForNewEvents
    }
}
