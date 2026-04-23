import SwiftUI
import SwiftData

struct CompletedTasksView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(CalendarManager.self) private var calendarManager
    @Query(filter: #Predicate<Task> { $0.isCompleted }, sort: \Task.createdAt, order: .reverse)
    private var tasks: [Task]
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
                Swift.Task { await calendarManager.removeSync(for: task) }
                modelContext.delete(task)
            }
        }
    }
}
