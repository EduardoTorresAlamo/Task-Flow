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
        // Building the snapshot reads SwiftData `@Model` objects, which must
        // stay on the main actor, so it happens synchronously here.
        let snapshot = WidgetSnapshot(
            generatedAt: .now,
            tasks: todaysTasks(in: context),
            projects: projects(in: context)
        )
        // The JSON encode + atomic file write and the WidgetKit reload touch
        // no SwiftData and can block on I/O. The only caller is the
        // scene-phase transition, so doing them inline would stall the app
        // lifecycle. Hand the finished (Sendable) snapshot to a detached task
        // so publication runs off the main thread.
        Swift.Task.detached(priority: .utility) {
            WidgetSnapshotStore.write(snapshot)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Defensive cap on the day-window fetch.
    ///
    /// The predicate already restricts the fetch to a single day's pending
    /// tasks, so realistic result sets are tiny. This cap only exists so a
    /// pathological day (hundreds of tasks) can never pull an unbounded number
    /// of `@Model` objects into the process. It is far larger than `maxTasks`
    /// so the in-memory priority sort below still sees every task it would
    /// render, keeping the "highest priority first" ordering exact.
    private static let fetchCap = 200

    /// Today's pending tasks, sorted by priority (high → low) then due time.
    ///
    /// The fetch is bounded two ways so it never loads the whole store into
    /// RAM: a `#Predicate` that keeps only *incomplete tasks whose due date
    /// falls inside today*, plus a `fetchLimit`. The day-window bounds are
    /// expressed with an explicit `!= nil` guard and force-unwrap — SwiftData
    /// lowers that to SQL, whereas nil-coalescing (`?? default`) inside a
    /// `#Predicate` is not expressible and traps when the fetch is built.
    private static func todaysTasks(in context: ModelContext) -> [WidgetTask] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: .now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        var descriptor = FetchDescriptor<Task>(
            predicate: #Predicate { task in
                !task.isCompleted
                    && task.dueDate != nil
                    && task.dueDate! >= startOfDay
                    && task.dueDate! < endOfDay
            },
            // Order in the store by due time; the priority-first ordering the
            // widget wants is layered on in memory over this small set.
            sortBy: [SortDescriptor(\.dueDate)]
        )
        descriptor.fetchLimit = fetchCap
        let pending = (try? context.fetch(descriptor)) ?? []

        return pending
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
    ///
    /// Pending counts come from a single tasks fetch grouped by project id,
    /// not from reading each project's `tasks` relationship. The old form
    /// faulted in every project's full task array — one query per project
    /// (N+1) — and then counted them in memory. Here one query over the
    /// incomplete tasks builds the whole `[projectID: count]` map at once.
    private static func projects(in context: ModelContext) -> [WidgetProject] {
        // One pass over incomplete tasks → pending count per project id.
        let pendingDescriptor = FetchDescriptor<Task>(predicate: #Predicate { !$0.isCompleted })
        let pendingTasks = (try? context.fetch(pendingDescriptor)) ?? []
        var pendingByProject: [UUID: Int] = [:]
        for task in pendingTasks {
            guard let projectID = task.project?.id else { continue }
            pendingByProject[projectID, default: 0] += 1
        }

        let descriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\.createdAt)])
        let all = (try? context.fetch(descriptor)) ?? []
        return all
            .map { project in
                WidgetProject(
                    id: project.id,
                    name: project.name,
                    colorHex: project.colorHex,
                    pendingCount: pendingByProject[project.id] ?? 0
                )
            }
            .sorted { $0.pendingCount > $1.pendingCount }
            .prefix(maxProjects)
            .map { $0 }
    }
}
