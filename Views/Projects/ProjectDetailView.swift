import SwiftUI
import SwiftData

/// The tasks belonging to one project.
///
/// Reuses the Inbox's dated sectioning and row treatment so a project reads as
/// a filtered view of the same list rather than a different kind of screen.
/// Completed tasks are shown in a trailing "Completed" section instead of a
/// separate screen, because within a project the recent history is context.
struct ProjectDetailView: View {
    /// The project whose tasks are listed.
    let project: Project

    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarManager.self) private var calendarManager

    /// The task currently open for editing.
    @State private var selectedTask: Task?

    /// Lazily-created view model that owns completion logic. `Optional` because
    /// `ModelContext` is only valid once the view has appeared.
    @State private var viewModel: InboxViewModel?

    /// The project's pending tasks, grouped by due date.
    ///
    /// Read off the relationship rather than a `@Query` with a predicate:
    /// SwiftData predicates cannot compare an optional to-one relationship
    /// against a captured model, and the per-project task count is small.
    private var groups: [DatedTaskGroup] {
        groupTasksBySection(project.tasks.filter { !$0.isCompleted })
    }

    /// The project's completed tasks, newest first.
    private var completed: [Task] {
        project.tasks
            .filter(\.isCompleted)
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    private var pendingCount: Int {
        project.tasks.filter { !$0.isCompleted }.count
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScreenHeader(
                    title: project.name,
                    subtitle: pendingCount == 1 ? "1 task pending" : "\(pendingCount) tasks pending"
                )

                if project.tasks.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    list
                }
            }
            .padding(.top, 8)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .tint(Theme.accent)
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
                Swift.Task {
                    await calendarManager.removeSync(for: task)
                    modelContext.delete(task)
                }
            }
        }
    }

    // MARK: - Pieces

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.sectionGap) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader(text: group.section.label)

                        VStack(spacing: Theme.rowGap) {
                            ForEach(group.tasks) { task in
                                TaskRowView(
                                    task: task,
                                    showsTimeOnly: group.section.showsTimeOnly,
                                    onTap: { selectedTask = task },
                                    onToggleComplete: {
                                        // Route completion through the view model so a
                                        // recurring task spawns its next occurrence.
                                        if let viewModel {
                                            Swift.Task { await viewModel.toggleCompletion(task) }
                                        }
                                    }
                                )
                            }
                        }
                    }
                }

                if !completed.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader(text: "Completed")

                        VStack(spacing: Theme.rowGap) {
                            ForEach(completed) { task in
                                TaskRowView(
                                    task: task,
                                    allowsSwipeToComplete: false,
                                    onTap: { selectedTask = task },
                                    onToggleComplete: {
                                        // Route un-completion through the view model so a
                                        // recurring task's spawned successor is cleaned up.
                                        if let viewModel {
                                            Swift.Task { await viewModel.toggleCompletion(task) }
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Theme.contentInset)
            .padding(.bottom, 24)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: project.symbolName)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Color(hex: project.colorHex).opacity(0.6))
            Text("No tasks in this project")
                .font(.tfRowTitle)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
