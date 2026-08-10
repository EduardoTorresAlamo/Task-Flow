import Foundation
import SwiftData
import WidgetKit

/// Publishes the widget's data from the app.
///
/// The widget cannot read SwiftData itself (see `WidgetSnapshot`), so the app
/// projects what the widget needs into a small `Codable` file in the App Group
/// and then asks WidgetKit to reload.
///
/// `@MainActor` because it reads a `ModelContext`.
@MainActor
enum WidgetSnapshotPublisher {

    /// How many task rows to publish. The largest family renders 12.
    private static let maxTasks = 12

    /// How many projects to publish for the summary strip and the picker.
    private static let maxProjects = 24

    /// Rebuilds the snapshot from the store and reloads the widget.
    ///
    /// Safe to call often: it is one fetch and one small file write.
    static func publish(from context: ModelContext) {
        let snapshot = WidgetSnapshot(
            generatedAt: .now,
            tasks: todaysTasks(in: context),
            projects: projects(in: context)
        )
        WidgetSnapshotStore.write(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Today's pending tasks, sorted by priority (high → low) then due time.
    ///
    /// The day window is applied in Swift rather than in the predicate:
    /// nil-coalescing an optional inside a `#Predicate` is not expressible as a
    /// SwiftData query and traps when the fetch is built.
    private static func todaysTasks(in context: ModelContext) -> [WidgetTask] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: .now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        let descriptor = FetchDescriptor<Task>(predicate: #Predicate { !$0.isCompleted })
        let pending = (try? context.fetch(descriptor)) ?? []

        return pending
            .filter { task in
                guard let due = task.dueDate else { return false }
                return due >= startOfDay && due < endOfDay
            }
            .sorted { lhs, rhs in
                if lhs.priority.rawValue != rhs.priority.rawValue {
                    return lhs.priority.rawValue > rhs.priority.rawValue
                }
                return (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
            }
            .prefix(maxTasks)
            .map { task in
                WidgetTask(
                    id: task.id,
                    title: task.title,
                    priorityRaw: task.priority.rawValue,
                    dueDate: task.dueDate,
                    projectColorHex: task.project?.colorHex,
                    projectID: task.project?.id
                )
            }
    }

    /// Every project with its pending count, busiest first.
    private static func projects(in context: ModelContext) -> [WidgetProject] {
        let descriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\.createdAt)])
        let all = (try? context.fetch(descriptor)) ?? []
        return all
            .map { project in
                WidgetProject(
                    id: project.id,
                    name: project.name,
                    colorHex: project.colorHex,
                    pendingCount: project.tasks.filter { !$0.isCompleted }.count
                )
            }
            .sorted { $0.pendingCount > $1.pendingCount }
            .prefix(maxProjects)
            .map { $0 }
    }
}
