import SwiftUI
import SwiftData

/// A screen listing all tasks the user has marked as completed.
///
/// Rows are grouped into "This Week" and "Earlier". Each row shows a restore
/// button that un-completes the task and returns it to the inbox, the task
/// title with strikethrough, and the completion timestamp. Tapping a row opens
/// `TaskEditView` so the user can re-schedule or delete the task permanently.
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

    /// Lazily-created view model that owns completion/restore logic. `Optional`
    /// because `ModelContext` is only valid once the view has appeared.
    @State private var viewModel: InboxViewModel?

    /// The completed tasks split into their time windows.
    private var groups: [CompletedGroup] { groupCompletedTasks(tasks) }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScreenHeader(title: "Done")

                if tasks.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    completedList
                }
            }
            .padding(.top, 8)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Create on first appear so modelContext is valid; guard against
            // re-creation on re-appear.
            if viewModel == nil {
                viewModel = InboxViewModel(modelContext: modelContext, calendarManager: calendarManager)
            }
        }
        .sheet(item: $selectedTask) { task in
            TaskEditView(task: task) {
                // Remove the EventKit events for the task and its subtasks first,
                // then delete inside the same async task. Deleting synchronously
                // here would invalidate the models before the scheduled
                // removeSyncTree could read their eventKitIdentifiers; the cascade
                // delete drops subtask rows but not their calendar events.
                Swift.Task {
                    await calendarManager.removeSyncTree(for: task)
                    modelContext.delete(task)
                }
            }
        }
    }

    // MARK: - Pieces

    private var completedList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.sectionGap) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader(text: group.section.label)

                        VStack(spacing: Theme.rowGap) {
                            ForEach(group.tasks) { task in
                                completedRow(task)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.contentInset)
            .padding(.bottom, 24)
        }
    }

    /// One archived task: restore control, struck-through title, and the
    /// moment it was completed.
    private func completedRow(_ task: Task) -> some View {
        GlassCard {
            HStack(spacing: 12) {
                // Restore button: routes through the view model so restoring a
                // recurring task also deletes the successor it spawned when it
                // was completed, instead of leaving a duplicate behind.
                Button {
                    guard let viewModel else { return }
                    Swift.Task { await viewModel.toggleCompletion(task) }
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.tfRowTitle)
                        .strikethrough(true, color: Theme.textTertiary)
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                    if let completedAt = task.completedAt {
                        Text(completedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.tfMeta)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Spacer(minLength: 4)
                PriorityBadge(priority: task.priority)
            }
        }
        // Tap on the card body (not the restore button) opens the edit sheet.
        .onTapGesture { selectedTask = task }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("Nothing completed yet")
                .font(.tfRowTitle)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
