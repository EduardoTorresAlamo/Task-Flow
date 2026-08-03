import WidgetKit
import SwiftUI

/// Renders `TodayTasksEntry` across the small, medium, and large families.
///
/// Each task row is wrapped in a `Link` to `taskflow://task/<id>` so tapping a
/// row opens the app on that task; the small family (which allows only a single
/// tap target) uses `.widgetURL` for the whole widget.
struct TodayTasksWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayTasksEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallLayout
        default:
            regularLayout
        }
    }

    /// Number of rows each family can comfortably show.
    private var visibleCount: Int {
        switch family {
        case .systemLarge:  return 7
        case .systemMedium: return 3
        default:            return 1
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "checklist")
                .font(.caption)
                .foregroundStyle(Color(hex: "#6E56CF"))
            Text(entry.projectName ?? "Today")
                .font(.caption).fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Spacer()
            if !entry.tasks.isEmpty {
                Text("\(entry.tasks.count)")
                    .font(.caption).fontWeight(.bold)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Small

    /// Compact single-focus layout: header, count, and the top-priority task.
    /// The whole widget deep-links to that task via `.widgetURL`.
    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let top = entry.tasks.first {
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    projectDot(top.projectColorHex)
                    Text(top.title)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                PriorityTag(priority: top.priority)
                if entry.tasks.count > 1 {
                    Text("+\(entry.tasks.count - 1) more")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(entry.tasks.first.flatMap { TaskDeepLink.url(for: $0.id) })
    }

    // MARK: - Medium / Large

    private var regularLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if entry.tasks.isEmpty {
                Spacer(minLength: 0)
                emptyState
                Spacer(minLength: 0)
            } else {
                VStack(spacing: 6) {
                    ForEach(entry.tasks.prefix(visibleCount)) { task in
                        if let url = TaskDeepLink.url(for: task.id) {
                            Link(destination: url) { row(task) }
                        } else {
                            row(task)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// A single task row: project color dot, title, due time, and priority badge.
    private func row(_ task: TaskSnapshot) -> some View {
        HStack(spacing: 8) {
            projectDot(task.projectColorHex)
            Text(task.title)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let due = task.dueDate {
                Text(due, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            PriorityTag(priority: task.priority)
        }
    }

    // MARK: - Pieces

    /// A small circular swatch of the owning project's color.
    @ViewBuilder
    private func projectDot(_ hex: String?) -> some View {
        Circle()
            .fill(hex.map { Color(hex: $0) } ?? Color.gray.opacity(0.4))
            .frame(width: 8, height: 8)
    }

    private var emptyState: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.green)
            Text("All clear for today")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

/// A compact priority badge sized for widget rows.
///
/// Mirrors the app's `PriorityBadge` color mapping but is defined here so the
/// widget target does not have to pull in the app's `Views` layer.
private struct PriorityTag: View {
    let priority: Priority

    private var color: Color {
        switch priority {
        case .none:   return .gray
        case .low:    return .blue
        case .medium: return .orange
        case .high:   return .red
        }
    }

    var body: some View {
        if priority != .none {
            Text(priority.label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(color.opacity(0.85))
                .clipShape(Capsule())
        }
    }
}
