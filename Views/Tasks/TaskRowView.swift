import SwiftUI

struct TaskRowView: View {
    @Bindable var task: Task
    var onTap: (() -> Void)? = nil

    private static let dueDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()

    var body: some View {
        GlassCard {

            HStack(spacing: 12) {
                Button {
                    task.isCompleted.toggle()
                    task.completedAt = task.isCompleted ? Date() : nil
                    task.updatedAt = Date()
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(task.isCompleted ? Color(hex: "#6E56CF") : .secondary)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .foregroundStyle(.white)
                        .strikethrough(task.isCompleted, color: .secondary)

                    if let due = task.dueDate {
                        Text(Self.dueDateFormatter.string(from: due))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                PriorityBadge(priority: task.priority)
            }
        }
        .onTapGesture { onTap?() }
    }
}
