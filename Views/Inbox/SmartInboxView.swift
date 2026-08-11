import SwiftUI
import SwiftData

/// The primary inbox screen showing all active (non-completed) tasks.
///
/// Displays a large title with a live pending count, a natural-language input
/// bar for quick task entry, and the task list grouped into dated sections
/// (Overdue / Today / Tomorrow / Later / Someday). Tapping a row opens
/// `TaskEditView` as a sheet.
///
/// `InboxViewModel` is created lazily on first appear so it can receive a
/// valid `ModelContext` from the SwiftUI environment, which is only available
/// after the view has been inserted into the view hierarchy.
struct SmartInboxView: View {
    /// SwiftData context used to construct `InboxViewModel` and to delete tasks.
    ///
    /// `@Environment(\.modelContext)` provides the context that is bound to
    /// the `ModelContainer` attached in `TaskFlowApp`. It is safe to access
    /// here because this view is always inside the `.modelContainer` scene modifier.
    @Environment(\.modelContext) private var modelContext

    /// Shared calendar manager for syncing tasks after deletion.
    @Environment(CalendarManager.self) private var calendarManager

    /// Carries the task id routed in from a widget `taskflow://` deep link.
    /// This view observes `pendingTaskID` and presents the matching task.
    @Environment(DeepLinkCoordinator.self) private var deepLinkCoordinator

    /// Live-updating list of active tasks, sorted newest-first.
    ///
    /// `@Query` hooks directly into SwiftData's change notifications, so the
    /// list updates automatically whenever a task is inserted, deleted, or
    /// has its `isCompleted` property toggled. The sort here only establishes
    /// a stable base order; `groupTasksBySection` re-sorts within each section.
    @Query(filter: #Predicate<Task> { !$0.isCompleted }, sort: \Task.createdAt, order: .reverse)
    private var tasks: [Task]

    /// The lazily-created view model. `Optional` because `ModelContext` is not
    /// available until the view appears for the first time.
    @State private var viewModel: InboxViewModel?

    /// The task currently selected for editing. Setting this non-nil presents
    /// `TaskEditView` as a sheet.
    @State private var selectedTask: Task?

    /// The tasks split into their dated sections, recomputed on every render so
    /// the grouping stays correct as the day rolls over.
    private var groups: [DatedTaskGroup] { groupTasksBySection(tasks) }

    /// The status line under the title.
    private var subtitle: String {
        tasks.count == 1 ? "1 task pending" : "\(tasks.count) tasks pending"
    }

    var body: some View {
        ZStack {
            // Full-bleed black background matches the dark-mode-first design.
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScreenHeader(title: "Inbox", subtitle: subtitle, showsWave: true)

                // Only render the input bar once the view model is available.
                if let vm = viewModel {
                    NaturalLanguageInputBar(viewModel: vm)
                        .padding(.bottom, 16)
                }

                if tasks.isEmpty {
                    Spacer()
                    emptyState
                    Spacer()
                } else {
                    taskList
                }
            }
            .padding(.top, 8)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            // Create the view model on first appear to ensure modelContext is valid.
            // Using `if viewModel == nil` prevents re-creation on re-appear,
            // which would discard any in-progress user input.
            if viewModel == nil {
                viewModel = InboxViewModel(modelContext: modelContext, calendarManager: calendarManager)
            }
            // A deep link may have arrived before this view existed; handle any
            // id already pending so a cold-launch tap still opens the task.
            presentDeepLinkedTask(deepLinkCoordinator.pendingTaskID)
        }
        // Present the task whenever a new deep link is routed in while the app runs.
        .onChange(of: deepLinkCoordinator.pendingTaskID) { _, id in
            presentDeepLinkedTask(id)
        }
        .sheet(item: $selectedTask) { task in
            TaskEditView(task: task) {
                // Remove the calendar event first, then delete the task inside the
                // same async task. Deleting synchronously here would invalidate the
                // model before the scheduled removeSync could read task.eventKitIdentifier.
                Swift.Task {
                    await calendarManager.removeSync(for: task)
                    modelContext.delete(task)
                }
            }
        }
    }

    // MARK: - Deep linking

    /// Resolves a deep-linked task id to its `Task` and presents it as a sheet,
    /// then clears the pending id so the same link is not re-handled.
    ///
    /// The task is fetched directly by id rather than searched in `tasks`, so a
    /// completed task (absent from the inbox query) still opens correctly.
    private func presentDeepLinkedTask(_ id: UUID?) {
        guard let id else { return }
        var descriptor = FetchDescriptor<Task>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let task = try? modelContext.fetch(descriptor).first {
            selectedTask = task
        }
        // Clear whether or not the task was found: a stale/deleted id should
        // not keep re-firing this handler on every state change.
        deepLinkCoordinator.pendingTaskID = nil
    }

    // MARK: - Pieces

    /// The grouped, scrolling task list.
    private var taskList: some View {
        ScrollView {
            // LazyVStack defers row rendering until each row scrolls
            // into the visible viewport, keeping memory usage low for
            // large task lists.
            LazyVStack(alignment: .leading, spacing: Theme.sectionGap) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        SectionHeader(text: group.section.label)

                        VStack(spacing: Theme.rowGap) {
                            ForEach(group.tasks) { task in
                                TaskRowView(
                                    task: task,
                                    showsTimeOnly: group.section.showsTimeOnly,
                                    isCataloging: viewModel?.catalogingTaskIDs.contains(task.id) ?? false,
                                    onTap: { selectedTask = task },
                                    onToggleComplete: {
                                        // Route completion through the view model so a
                                        // recurring task spawns its next occurrence.
                                        if let vm = viewModel {
                                            Swift.Task { await vm.toggleCompletion(task) }
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
            // Section membership changes when a task's due date is edited;
            // animating on the group shape keeps rows from jumping between
            // headings without a transition.
            .animation(.easeInOut(duration: 0.22), value: groups.map(\.id))
        }
    }

    /// Shown when nothing is pending.
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.textTertiary)
            Text("All clear")
                .font(.tfRowTitle)
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
