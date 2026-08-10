import Foundation

/// The buckets the Inbox groups its tasks into.
///
/// The Airy Grouped design leads with an uppercase section label above each
/// run of cards, so the list needs a stable, ordered set of buckets rather
/// than one flat array. `Int` raw values give the sections their display order
/// for free via `Comparable` on the raw value.
enum TaskSection: Int, CaseIterable, Identifiable {
    /// Tasks whose due date has already passed. Surfaced first because they
    /// are the only bucket that demands action right now.
    case overdue = 0
    /// Due at some point during the current calendar day.
    case today = 1
    /// Due during the next calendar day.
    case tomorrow = 2
    /// Due after tomorrow.
    case later = 3
    /// No due date at all. Last, because nothing about them is time-bound.
    case someday = 4

    var id: Int { rawValue }

    /// The uppercase label rendered by `SectionHeader`.
    var label: String {
        switch self {
        case .overdue:  return "Overdue"
        case .today:    return "Today"
        case .tomorrow: return "Tomorrow"
        case .later:    return "Later"
        case .someday:  return "Someday"
        }
    }

    /// Whether rows in this section show a time-only due stamp.
    ///
    /// Inside Today and Tomorrow the calendar date is already stated by the
    /// section label, so repeating "Aug 11" on every row is noise; sections
    /// that span multiple days keep the full date.
    var showsTimeOnly: Bool {
        self == .today || self == .tomorrow
    }

    /// Classifies a due date into its section.
    ///
    /// A task due earlier *today* still counts as Today rather than Overdue:
    /// the day is the unit the sections are built on, and demoting a 9am task
    /// at 9:01am would shuffle the list under the user mid-morning.
    ///
    /// - Parameters:
    ///   - dueDate: The task's deadline, or `nil` for an undated task.
    ///   - now: The reference instant, injectable so the logic is testable.
    ///   - calendar: The calendar used for day-boundary math.
    /// - Returns: The section the task belongs in.
    static func section(
        for dueDate: Date?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> TaskSection {
        guard let dueDate else { return .someday }
        if calendar.isDate(dueDate, inSameDayAs: now) { return .today }
        if dueDate < calendar.startOfDay(for: now) { return .overdue }
        if calendar.isDateInTomorrow(dueDate) { return .tomorrow }
        return .later
    }
}

/// One rendered group: a section and the tasks that fall into it.
///
/// A struct rather than a `(TaskSection, [Task])` tuple so `ForEach` can key
/// off a stable `Identifiable` conformance.
///
/// Named `DatedTaskGroup` rather than `TaskGroup` because the latter would
/// shadow the standard library's concurrency `TaskGroup` module-wide, which
/// would silently break any future `withTaskGroup` call site.
struct DatedTaskGroup: Identifiable {
    let section: TaskSection
    let tasks: [Task]

    var id: Int { section.rawValue }
}

/// Splits a flat task list into ordered, non-empty groups.
///
/// Empty sections are dropped rather than rendered as a bare label, so a user
/// with only undated tasks sees one "SOMEDAY" heading instead of five headings
/// with nothing beneath four of them.
///
/// - Parameters:
///   - tasks: The tasks to group, in any order.
///   - now: The reference instant used for the day-boundary comparisons.
/// - Returns: Groups in section order, each sorted by due date then title.
func groupTasksBySection(_ tasks: [Task], now: Date = .now) -> [DatedTaskGroup] {
    let buckets = Dictionary(grouping: tasks) { TaskSection.section(for: $0.dueDate, now: now) }
    return TaskSection.allCases.compactMap { section in
        guard let bucket = buckets[section], !bucket.isEmpty else { return nil }
        let sorted = bucket.sorted { lhs, rhs in
            // Undated tasks (only possible in .someday) fall back to title order.
            switch (lhs.dueDate, rhs.dueDate) {
            case let (l?, r?) where l != r: return l < r
            case (nil, _?): return false
            case (_?, nil): return true
            default: return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }
        }
        return DatedTaskGroup(section: section, tasks: sorted)
    }
}

/// The buckets the Done screen groups completed tasks into.
enum CompletedSection: Int, CaseIterable, Identifiable {
    /// Completed within the last seven days.
    case thisWeek = 0
    /// Completed before that.
    case earlier = 1

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .thisWeek: return "This Week"
        case .earlier:  return "Earlier"
        }
    }
}

/// One rendered group of completed tasks.
struct CompletedGroup: Identifiable {
    let section: CompletedSection
    let tasks: [Task]

    var id: Int { section.rawValue }
}

/// Splits completed tasks into "this week" and "earlier", newest first.
///
/// Tasks with no `completedAt` timestamp (possible for records written before
/// the timestamp existed) are treated as older than the window rather than
/// dropped, so nothing silently vanishes from the archive.
///
/// - Parameters:
///   - tasks: The completed tasks to group.
///   - now: The reference instant used for the seven-day window.
/// - Returns: Non-empty groups in section order.
func groupCompletedTasks(_ tasks: [Task], now: Date = .now) -> [CompletedGroup] {
    let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
    let buckets = Dictionary(grouping: tasks) { task -> CompletedSection in
        guard let completedAt = task.completedAt else { return .earlier }
        return completedAt >= cutoff ? .thisWeek : .earlier
    }
    return CompletedSection.allCases.compactMap { section in
        guard let bucket = buckets[section], !bucket.isEmpty else { return nil }
        let sorted = bucket.sorted {
            ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast)
        }
        return CompletedGroup(section: section, tasks: sorted)
    }
}
