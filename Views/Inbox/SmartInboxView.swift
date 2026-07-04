import SwiftUI
import SwiftData

/// The primary inbox screen showing all active (non-completed) tasks.
///
/// Displays a natural-language input bar at the top for quick task entry
/// and a scrollable list of task rows below. Tapping a row opens `TaskEditView`
/// as a sheet.
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

    /// Live-updating list of active tasks, sorted newest-first.
    ///
    /// `@Query` hooks directly into SwiftData's change notifications, so the
    /// list updates automatically whenever a task is inserted, deleted, or
    /// has its `isCompleted` property toggled.
    @Query(filter: #Predicate<Task> { !$0.isCompleted }, sort: \Task.createdAt, order: .reverse)
    private var tasks: [Task]

    /// The lazily-created view model. `Optional` because `ModelContext` is not
    /// available until the view appears for the first time.
    @State private var viewModel: InboxViewModel?

    /// The task currently selected for editing. Setting this non-nil presents
    /// `TaskEditView` as a sheet.
    @State private var selectedTask: Task?

    var body: some View {
        ZStack {
            // Full-bleed black background matches the dark-mode-first design.
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
                // Only render the input bar once the view model is available.
                if let vm = viewModel {
                    NaturalLanguageInputBar(viewModel: vm)
                }

                if tasks.isEmpty {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("All clear")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                } else {
                    ScrollView {
                        // LazyVStack defers row rendering until each row scrolls
                        // into the visible viewport, keeping memory usage low for
                        // large task lists.
                        LazyVStack(spacing: 8) {
                            ForEach(tasks) { task in
                                TaskRowView(task: task, onTap: { selectedTask = task })
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            .padding(.top, 8)
        }
        .navigationTitle("Inbox")
        .preferredColorScheme(.dark)
        .onAppear {
            // Create the view model on first appear to ensure modelContext is valid.
            // Using `if viewModel == nil` prevents re-creation on re-appear,
            // which would discard any in-progress user input.
            if viewModel == nil {
                viewModel = InboxViewModel(modelContext: modelContext, calendarManager: calendarManager)
            }
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
}
