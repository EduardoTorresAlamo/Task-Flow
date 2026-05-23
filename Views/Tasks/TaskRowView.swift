import SwiftUI

/// A single row in the task list representing one `Task`.
///
/// Displays a completion toggle button, the task title with optional strikethrough
/// for completed tasks, the formatted due date, and a priority badge.
/// Tapping the row (outside the toggle) fires the `onTap` callback so the
/// parent view can present `TaskEditView`.
struct TaskRowView: View {
    /// The task to display. `@Bindable` enables the completion toggle to write
    /// `task.isCompleted`, `task.completedAt`, and `task.updatedAt` directly to
    /// the SwiftData store without an intermediate `@State` copy.
    @Bindable var task: Task

    /// Optional callback invoked when the user taps the row (not the toggle button).
    /// Defaults to `nil` so rows can be used in read-only contexts without a handler.
    var onTap: (() -> Void)? = nil

    /// Shared, statically-allocated date formatter used across all row instances.
    ///
    /// `static let` ensures only one formatter is ever created, regardless of how
    /// many rows are on screen, which is measurably faster than per-instance creation
    /// when the list is long.
    private static let dueDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()

    var body: some View {
        GlassCard {
            HStack(spacing: 12) {
                // Completion toggle button: directly mutates the @Bindable task
                // properties so the change is persisted to SwiftData immediately.
                Button {
                    task.isCompleted.toggle()
                    // Record or clear the completion timestamp in sync with the flag.
                    task.completedAt = task.isCompleted ? Date() : nil
                    task.updatedAt = Date()
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(task.isCompleted ? Color(hex: "#6E56CF") : .secondary)
                }
                .buttonStyle(.plain) // Prevents the button style from consuming the whole row tap area.

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .foregroundStyle(.white)
                        // Strikethrough is applied only when completed so the style
                        // reflects the current state without a separate Text branch.
                        .strikethrough(task.isCompleted, color: .secondary)

                    if let due = task.dueDate {
                        Text(Self.dueDateFormatter.string(from: due))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // PriorityBadge renders nothing for .none priority, so no guard needed.
                PriorityBadge(priority: task.priority)
            }
        }
        // Tap gesture on the card itself (not the toggle) opens the edit sheet.
        .onTapGesture { onTap?() }
    }
}
