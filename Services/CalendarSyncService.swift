import EventKit
import Observation

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
            ekEvent.calendar = store.defaultCalendarForNewEvents
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

        // Mirror the task's recurrence onto the calendar event so a repeating
        // task produces a repeating EKEvent. Setting to nil clears any rule
        // that was present on a previously-recurring event.
        if let rule = task.recurrenceRule {
            ekEvent.recurrenceRules = [Self.ekRecurrenceRule(from: rule)]
        } else {
            ekEvent.recurrenceRules = nil
        }

        do {
            // .thisEvent applies the save to only this occurrence, not recurring ones.
            try store.save(ekEvent, span: .thisEvent)
            // Persist the stable identifier so we can re-find this event later.
            task.eventKitIdentifier = ekEvent.eventIdentifier
        } catch {
            // Save failed -- eventKitIdentifier remains unchanged
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
            // Removal failed -- identifier preserved so retry is possible
        }
    }

    // MARK: - Recurrence Mapping

    /// Translates a Task-Flow `RecurrenceRule` into the equivalent EventKit
    /// `EKRecurrenceRule` so a repeating task mirrors as a repeating event.
    ///
    /// The rule's `endDate` takes precedence for the recurrence end; if absent,
    /// a `maxOccurrences` cap is expressed as an occurrence-count end. `.weekdays`
    /// is modelled as a weekly rule constrained to Monday-Friday, and `.biweekly`
    /// as a weekly rule with a two-week interval.
    ///
    /// - Parameter rule: The task's recurrence specification.
    /// - Returns: A configured `EKRecurrenceRule`.
    private static func ekRecurrenceRule(from rule: RecurrenceRule) -> EKRecurrenceRule {
        let end: EKRecurrenceEnd?
        if let endDate = rule.endDate {
            end = EKRecurrenceEnd(end: endDate)
        } else if let maxOccurrences = rule.maxOccurrences {
            end = EKRecurrenceEnd(occurrenceCount: maxOccurrences)
        } else {
            end = nil
        }

        switch rule.frequency {
        case .daily:
            return EKRecurrenceRule(recurrenceWith: .daily, interval: rule.interval, end: end)
        case .yearly:
            return EKRecurrenceRule(recurrenceWith: .yearly, interval: rule.interval, end: end)
        case .weekdays:
            let businessDays = Weekday.allCases
                .filter(\.isBusinessDay)
                .map { EKRecurrenceDayOfWeek(ekWeekday($0)) }
            return EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 1,
                daysOfTheWeek: businessDays,
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: end
            )
        case .weekly(let day):
            return EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: rule.interval,
                daysOfTheWeek: [EKRecurrenceDayOfWeek(ekWeekday(day))],
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: end
            )
        case .biweekly(let day):
            return EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 2,
                daysOfTheWeek: [EKRecurrenceDayOfWeek(ekWeekday(day))],
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: end
            )
        case .monthly(let day):
            return EKRecurrenceRule(
                recurrenceWith: .monthly,
                interval: rule.interval,
                daysOfTheWeek: nil,
                daysOfTheMonth: [NSNumber(value: day)],
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: end
            )
        }
    }

    /// Maps a Task-Flow `Weekday` to its EventKit counterpart. Both use the
    /// Sunday = 1 ... Saturday = 7 numbering, so the raw value maps directly.
    private static func ekWeekday(_ weekday: Weekday) -> EKWeekday {
        EKWeekday(rawValue: weekday.rawValue) ?? .monday
    }
}
