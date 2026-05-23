import SwiftUI
import SwiftData

/// A screen listing all tasks the user has marked as completed.
///
/// Each row shows a "restore" button that un-completes the task and returns it
/// to the inbox, the task title with strikethrough, and the completion timestamp.
/// Tapping a row opens `TaskEditView` so the user can re-schedule or delete
/// the task permanently.
struct CompletedTasksView: View {
    /// SwiftData context used to delete tasks permanently.
    @Environment(\.modelContext) private var modelContext

    /// Calendar manager for removing the linked EventKit event when a task is deleted.
    @Environment(CalendarManager.self) private var calendarManager

    /// Live-updating list of completed tasks, sorted newest-first.
    ///
    /// `@Query` re-evaluates the predicate automatically whenever any task's
    /// `isCompleted` property changes, so restoring a task from this view removes
    /// it from the list without any manual state management.
    @Query(filter: #Predicate<Task> { $0.isCompleted }, sort: \Task.createdAt, order: .reverse)
    private var tasks: [Task]

    /// The task currently selected for editing via the sheet.
    @State private var selectedTask: Task?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if tasks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Nothing completed yet")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(tasks) { task in
                                GlassCard {
                                    HStack(spacing: 12) {
                                        // Restore button: flips isCompleted back to false
                                        // and clears the completion timestamp so the task
                                        // re-appears in the inbox @Query result.
                                        Button {
                                            task.isCompleted = false
                                            task.completedAt = nil
                                            task.updatedAt = Date()
                                        } label: {
                                            Image(systemName: "arrow.uturn.backward.circle")
                                                .font(.title3)
                                                .foregroundStyle(Color(hex: "#6E56CF"))
                                        }
                                        .buttonStyle(.plain)

                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(task.title)
                                                .strikethrough(true, color: .secondary)
                                                .foregroundStyle(.white)
                                            if let completedAt = task.completedAt {
                                                Text("Completed \(completedAt.formatted(date: .abbreviated, time: .shortened))")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }

                                        Spacer()
                                        PriorityBadge(priority: task.priority)
                                    }
                                }
                                // Tap on the card body (not the restore button) opens the edit sheet.
                                .onTapGesture { selectedTask = task }
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .navigationTitle("Done")
            .preferredColorScheme(.dark)
        }
        .sheet(item: $selectedTask) { task in
            TaskEditView(task: task) {
                // Remove the EventKit event before deleting the task so
                // CalendarSyncService can still read task.eventKitIdentifier.
                Swift.Task { await calendarManager.removeSync(for: task) }
                modelContext.delete(task)
            }
        }
    }
}
