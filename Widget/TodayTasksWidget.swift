import WidgetKit
import SwiftUI
import SwiftData

/// A lightweight, `Sendable` value snapshot of a `Task` for widget rendering.
///
/// SwiftData `@Model` objects are not `Sendable` and are tied to their
/// `ModelContext`, so they must not cross into the timeline/view layer. The
/// provider projects each fetched task into this immutable struct instead.
struct TaskSnapshot: Identifiable, Hashable {
    let id: UUID
    let title: String
    let priority: Priority
    let dueDate: Date?
    /// Hex color of the owning project, or `nil` for tasks with no project.
    let projectColorHex: String?
}

/// A per-project pending count, shown in the extra-large family's footer strip.
struct ProjectSummary: Identifiable, Hashable {
    let id: UUID
    let name: String
    let colorHex: String
    /// Pending (non-completed) tasks in this project, across all dates.
    let count: Int
}

/// One timeline entry: the tasks to show at a given render time.
struct TodayTasksEntry: TimelineEntry {
    let date: Date
    let tasks: [TaskSnapshot]
    /// Name of the filtered project, or `nil` when showing all projects.
    let projectName: String?
    /// Pending counts for the busiest projects. Only the extra-large family
    /// renders these; smaller families ignore the field.
    let projectSummaries: [ProjectSummary]

    /// Placeholder content shown in the widget gallery and while loading.
    static let placeholder = TodayTasksEntry(
        date: .now,
        tasks: [
            TaskSnapshot(id: UUID(), title: "Call Dentist", priority: .medium, dueDate: .now, projectColorHex: "#9184D9"),
            TaskSnapshot(id: UUID(), title: "Team Standup", priority: .none, dueDate: .now, projectColorHex: "#9184D9"),
            TaskSnapshot(id: UUID(), title: "Review Q3 Budget", priority: .high, dueDate: .now, projectColorHex: "#4D8FE0")
        ],
        projectName: nil,
        projectSummaries: [
            ProjectSummary(id: UUID(), name: "Personal", colorHex: "#9184D9", count: 4),
            ProjectSummary(id: UUID(), name: "Work", colorHex: "#4D8FE0", count: 7),
            ProjectSummary(id: UUID(), name: "Home", colorHex: "#5FBF8F", count: 2)
        ]
    )
}

/// Supplies timeline entries by reading today's pending tasks from the shared store.
struct TodayTasksProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TodayTasksEntry {
        .placeholder
    }

    func snapshot(for configuration: ProjectFilterIntent, in context: Context) async -> TodayTasksEntry {
        await makeEntry(for: configuration)
    }

    func timeline(for configuration: ProjectFilterIntent, in context: Context) async -> Timeline<TodayTasksEntry> {
        let entry = await makeEntry(for: configuration)
        // Refresh twice an hour so due-date relative text and the today-window
        // stay reasonably fresh without hammering the widget budget.
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now)
            ?? Date(timeIntervalSinceNow: 1800)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    /// Fetches today's incomplete tasks, applies the project filter, and sorts
    /// by priority (high → low), then by due time.
    @MainActor
    private func makeEntry(for configuration: ProjectFilterIntent) async -> TodayTasksEntry {
        let context = TaskFlowContainer.makeShared().mainContext

        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: .now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay
        // Sentinel used so nil-due tasks fall outside the today window in the predicate.
        let farPast = Date.distantPast

        let descriptor = FetchDescriptor<Task>(
            predicate: #Predicate { task in
                !task.isCompleted
                    && (task.dueDate ?? farPast) >= startOfDay
                    && (task.dueDate ?? farPast) < endOfDay
            }
        )

        let fetched = (try? context.fetch(descriptor)) ?? []

        // Filter by the configured project in memory (robust across optional
        // relationships) and sort by priority then due time.
        let filtered: [Task]
        if let projectID = configuration.project?.id {
            filtered = fetched.filter { $0.project?.id == projectID }
        } else {
            filtered = fetched
        }

        let sorted = filtered.sorted { lhs, rhs in
            if lhs.priority.rawValue != rhs.priority.rawValue {
                return lhs.priority.rawValue > rhs.priority.rawValue
            }
            return (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
        }

        // Cap at what the largest family can show; the view slices per family.
        let snapshots = sorted.prefix(12).map { task in
            TaskSnapshot(
                id: task.id,
                title: task.title,
                priority: task.priority,
                dueDate: task.dueDate,
                projectColorHex: task.project?.colorHex
            )
        }

        return TodayTasksEntry(
            date: .now,
            tasks: Array(snapshots),
            projectName: configuration.project?.name,
            projectSummaries: projectSummaries(in: context)
        )
    }

    /// The three busiest projects by pending task count.
    ///
    /// Deliberately not restricted to today's window: the footer strip answers
    /// "where is my outstanding work" rather than "what is due in the next few
    /// hours", which the rows above it already cover.
    @MainActor
    private func projectSummaries(in context: ModelContext) -> [ProjectSummary] {
        let descriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\.createdAt)])
        let projects = (try? context.fetch(descriptor)) ?? []
        return projects
            .map { project in
                ProjectSummary(
                    id: project.id,
                    name: project.name,
                    colorHex: project.colorHex,
                    count: project.tasks.filter { !$0.isCompleted }.count
                )
            }
            .filter { $0.count > 0 }
            .sorted { $0.count > $1.count }
            .prefix(3)
            .map { $0 }
    }
}

/// The Today's Tasks widget: an in-place configurable, priority-sorted list.
struct TodayTasksWidget: Widget {
    static let kind = "TodayTasksWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: Self.kind,
            intent: ProjectFilterIntent.self,
            provider: TodayTasksProvider()
        ) { entry in
            TodayTasksWidgetView(entry: entry)
                // The wave ground is a full view rather than a color so the
                // radial blooms can be sized against the widget's own bounds.
                // Accessory (Lock Screen) families composite as a monochrome
                // vibrant layer, so they are given no background at all.
                .containerBackground(for: .widget) { WidgetWaveBackground() }
        }
        .configurationDisplayName("Today's Tasks")
        .description("Your pending tasks for today, sorted by priority.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
            // Both extra-large families: the landscape one (iPad, iOS 15+) and
            // systemExtraLargePortrait, added in iOS 27. The deployment target
            // is iOS 27, so neither needs an availability check.
            .systemExtraLarge, .systemExtraLargePortrait,
            .accessoryRectangular, .accessoryCircular
        ])
    }
}
