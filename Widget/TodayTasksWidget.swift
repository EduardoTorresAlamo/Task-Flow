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

/// One timeline entry: the tasks to show at a given render time.
struct TodayTasksEntry: TimelineEntry {
    let date: Date
    let tasks: [TaskSnapshot]
    /// Name of the filtered project, or `nil` when showing all projects.
    let projectName: String?

    /// Placeholder content shown in the widget gallery and while loading.
    static let placeholder = TodayTasksEntry(
        date: .now,
        tasks: [
            TaskSnapshot(id: UUID(), title: "Review pull request", priority: .high, dueDate: .now, projectColorHex: "#6E56CF"),
            TaskSnapshot(id: UUID(), title: "Reply to design feedback", priority: .medium, dueDate: .now, projectColorHex: "#22C55E"),
            TaskSnapshot(id: UUID(), title: "Book flights", priority: .low, dueDate: .now, projectColorHex: "#F59E0B")
        ],
        projectName: nil
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
            projectName: configuration.project?.name
        )
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
                .containerBackground(.black.gradient, for: .widget)
        }
        .configurationDisplayName("Today's Tasks")
        .description("Your pending tasks for today, sorted by priority.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
