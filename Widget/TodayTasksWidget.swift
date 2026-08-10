import WidgetKit
import SwiftUI

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

    /// Set when the shared store could not be opened.
    ///
    /// The widget renders this instead of an empty list, because "no tasks" and
    /// "could not read your tasks" are different things and showing the first
    /// when the second is true is a lie the user cannot debug.
    var loadError: String? = nil

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

/// Supplies timeline entries by decoding the snapshot the app publishes.
///
/// Contains no SwiftData at all, deliberately — see `WidgetSnapshot` for why.
/// That also makes the provider synchronous and effectively free: one small
/// file read, no container, no schema, no fetch.
struct TodayTasksProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TodayTasksEntry {
        .placeholder
    }

    func snapshot(for configuration: ProjectFilterIntent, in context: Context) async -> TodayTasksEntry {
        makeEntry(for: configuration)
    }

    func timeline(for configuration: ProjectFilterIntent, in context: Context) async -> Timeline<TodayTasksEntry> {
        let entry = makeEntry(for: configuration)
        // Refresh twice an hour so due-date relative text and the today-window
        // stay reasonably fresh without hammering the widget budget. The app
        // also reloads the timeline directly whenever it publishes a snapshot,
        // so this is only the floor, not the usual path.
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 30, to: .now)
            ?? Date(timeIntervalSinceNow: 1800)
        return Timeline(entries: [entry], policy: .after(nextRefresh))
    }

    /// Builds the entry from the published snapshot, applying the project filter.
    private func makeEntry(for configuration: ProjectFilterIntent) -> TodayTasksEntry {
        let snapshot = WidgetSnapshotStore.read()

        let selectedProject = configuration.project?.id
        let tasks = snapshot.tasks
            .filter { selectedProject == nil || $0.projectID == selectedProject }
            .map { task in
                TaskSnapshot(
                    id: task.id,
                    title: task.title,
                    priority: Priority(rawValue: task.priorityRaw) ?? .none,
                    dueDate: task.dueDate,
                    projectColorHex: task.projectColorHex
                )
            }

        let summaries = snapshot.projects
            .filter { $0.pendingCount > 0 }
            .prefix(3)
            .map { ProjectSummary(id: $0.id, name: $0.name, colorHex: $0.colorHex, count: $0.pendingCount) }

        return TodayTasksEntry(
            date: .now,
            tasks: tasks,
            projectName: configuration.project?.name,
            projectSummaries: Array(summaries),
            // The app has never run, so there is nothing to show and saying so
            // beats an empty list that looks like "you are all caught up".
            loadError: snapshot.generatedAt == .distantPast
                ? "Open Task Flow once to set up the widget."
                : nil
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
