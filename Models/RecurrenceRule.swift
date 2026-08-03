import Foundation

/// A day of the week.
///
/// Raw `Int` values follow Foundation's `Calendar` weekday numbering
/// (Sunday = 1 ... Saturday = 7) so a `Weekday` maps directly onto
/// `Calendar` date math and EventKit's `EKWeekday` without a lookup table.
/// `Codable` conformance lets it be persisted as part of a `RecurrenceRule`
/// inside SwiftData; `Sendable` keeps it usable across the app's `@Sendable`
/// closures under Swift 6 strict concurrency.
enum Weekday: Int, Codable, CaseIterable, Sendable, Identifiable, Hashable {
    case sunday = 1
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday

    /// Stable identity for use in SwiftUI `ForEach` and `Picker`.
    var id: Int { rawValue }

    /// The full human-readable name shown in pickers and rule descriptions.
    var label: String {
        switch self {
        case .sunday:    return "Sunday"
        case .monday:    return "Monday"
        case .tuesday:   return "Tuesday"
        case .wednesday: return "Wednesday"
        case .thursday:  return "Thursday"
        case .friday:    return "Friday"
        case .saturday:  return "Saturday"
        }
    }

    /// `true` for Monday through Friday, used by the `.weekdays` frequency.
    var isBusinessDay: Bool {
        self != .saturday && self != .sunday
    }

    /// The `Weekday` for the given date under the supplied calendar.
    ///
    /// - Parameters:
    ///   - date: The date whose weekday is required.
    ///   - calendar: The calendar to interpret the date in; defaults to `.current`.
    /// - Returns: The matching `Weekday`, or `.monday` as a safe fallback if the
    ///   calendar returns an out-of-range component (which it never does in practice).
    static func from(_ date: Date, calendar: Calendar = .current) -> Weekday {
        Weekday(rawValue: calendar.component(.weekday, from: date)) ?? .monday
    }
}

/// The cadence of a recurrence, independent of any end constraints.
///
/// This is the enum of recurrence *types*. End conditions (`endDate`,
/// `maxOccurrences`) and the numeric multiplier (`interval`) live on the
/// wrapping `RecurrenceRule` because Swift enums cannot carry stored
/// properties shared across all cases.
enum RecurrenceFrequency: Codable, Hashable, Sendable {
    /// Repeats every day (subject to `RecurrenceRule.interval`).
    case daily
    /// Repeats Monday through Friday, skipping weekends.
    case weekdays
    /// Repeats every week on the given weekday.
    case weekly(day: Weekday)
    /// Repeats every two weeks on the given weekday.
    case biweekly(day: Weekday)
    /// Repeats every month on the given day-of-month (1...31, clamped per month).
    case monthly(day: Int)
    /// Repeats every year on the anchor date's month and day.
    case yearly
}

/// A complete recurrence specification for a `Task`.
///
/// Wraps a `RecurrenceFrequency` with a numeric `interval` multiplier and the
/// two optional end conditions required by the feature spec: a hard `endDate`
/// cutoff and a `maxOccurrences` cap. Stored on `Task` as a single `Codable`
/// SwiftData attribute.
struct RecurrenceRule: Codable, Hashable, Sendable {
    /// The base cadence of the recurrence.
    var frequency: RecurrenceFrequency

    /// The multiplier applied to `frequency` (e.g. `interval == 2` with
    /// `.daily` means "every 2 days"). Always at least 1.
    var interval: Int

    /// An optional date after which no further occurrences are generated.
    var endDate: Date?

    /// An optional cap on the total number of occurrences ever generated,
    /// counting the original task as the first occurrence.
    var maxOccurrences: Int?

    /// Creates a recurrence rule.
    ///
    /// - Parameters:
    ///   - frequency: The base cadence.
    ///   - interval: The multiplier applied to the frequency; clamped to a
    ///     minimum of 1. Defaults to 1.
    ///   - endDate: Optional hard cutoff date. Defaults to `nil` (no cutoff).
    ///   - maxOccurrences: Optional occurrence cap. Defaults to `nil` (unlimited).
    init(frequency: RecurrenceFrequency, interval: Int = 1, endDate: Date? = nil, maxOccurrences: Int? = nil) {
        self.frequency = frequency
        self.interval = max(1, interval)
        self.endDate = endDate
        self.maxOccurrences = maxOccurrences
    }

    /// A concise human-readable description for menus and row subtitles.
    var label: String {
        let base: String
        switch frequency {
        case .daily:
            base = interval == 1 ? "Daily" : "Every \(interval) days"
        case .weekdays:
            base = "Weekdays"
        case .weekly(let day):
            base = interval == 1 ? "Weekly on \(day.label)" : "Every \(interval) weeks on \(day.label)"
        case .biweekly(let day):
            base = "Every 2 weeks on \(day.label)"
        case .monthly(let day):
            base = interval == 1 ? "Monthly on day \(day)" : "Every \(interval) months on day \(day)"
        case .yearly:
            base = interval == 1 ? "Yearly" : "Every \(interval) years"
        }
        return base
    }

    /// Computes the first occurrence date strictly after `date`, or `nil` when
    /// the recurrence has passed its `endDate`.
    ///
    /// The `maxOccurrences` cap is not evaluated here because it depends on how
    /// many occurrences have already been generated, which lives on the owning
    /// `Task`; see `Task.makeNextOccurrence(calendar:)`.
    ///
    /// - Parameters:
    ///   - date: The anchor date to advance from (typically the current due date).
    ///   - calendar: The calendar used for all date arithmetic; defaults to `.current`.
    /// - Returns: The next occurrence, or `nil` if it would fall after `endDate`.
    func nextDate(after date: Date, calendar: Calendar = .current) -> Date? {
        let candidate: Date?
        switch frequency {
        case .daily:
            candidate = calendar.date(byAdding: .day, value: interval, to: date)
        case .weekdays:
            candidate = Self.nextBusinessDay(after: date, calendar: calendar)
        case .weekly:
            candidate = calendar.date(byAdding: .day, value: 7 * interval, to: date)
        case .biweekly:
            candidate = calendar.date(byAdding: .day, value: 14, to: date)
        case .monthly(let day):
            candidate = Self.nextMonthly(after: date, day: day, interval: interval, calendar: calendar)
        case .yearly:
            candidate = calendar.date(byAdding: .year, value: interval, to: date)
        }
        guard let next = candidate else { return nil }
        if let endDate, next > endDate { return nil }
        return next
    }

    // MARK: - Date Helpers

    /// Returns the next Monday-Friday date after `date`, skipping weekends.
    private static func nextBusinessDay(after date: Date, calendar: Calendar) -> Date? {
        var cursor = date
        for _ in 0..<7 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { return nil }
            cursor = next
            if Weekday.from(cursor, calendar: calendar).isBusinessDay { return cursor }
        }
        return nil
    }

    /// Advances `date` by `interval` months and pins the result to `day`,
    /// clamping to the last valid day of the target month (e.g. day 31 in
    /// February becomes the 28th/29th). Time-of-day is preserved from `date`.
    private static func nextMonthly(after date: Date, day: Int, interval: Int, calendar: Calendar) -> Date? {
        guard let shifted = calendar.date(byAdding: .month, value: interval, to: date) else { return nil }
        let range = calendar.range(of: .day, in: .month, for: shifted)
        let clampedDay = min(day, range?.upperBound.advanced(by: -1) ?? day)
        var components = calendar.dateComponents([.year, .month, .hour, .minute, .second], from: shifted)
        components.day = clampedDay
        return calendar.date(from: components)
    }
}
