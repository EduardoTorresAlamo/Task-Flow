import SwiftUI
import SwiftData

struct SmartInboxView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarManager.self) private var calendarManager
    @Query(filter: #Predicate<Task> { !$0.isCompleted }, sort: \Task.createdAt, order: .reverse)
    private var tasks: [Task]

    @State private var viewModel: InboxViewModel?
    @State private var selectedTask: Task?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 12) {
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
            if viewModel == nil {
                viewModel = InboxViewModel(modelContext: modelContext, calendarManager: calendarManager)
            }
        }
        .sheet(item: $selectedTask) { task in
            TaskEditView(task: task) {
                Swift.Task { await calendarManager.removeSync(for: task) }
                modelContext.delete(task)
            }
        }
    }
}
