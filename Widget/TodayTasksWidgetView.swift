import WidgetKit
import SwiftUI

/// Renders `TodayTasksEntry` across every supported family.
///
/// Home Screen families (small through extra large) get the design's
/// wave-textured ground: soft radial blooms in the accent and a warm secondary,
/// echoing the app icon's wave without drawing it literally. Lock Screen
/// families are rendered flat, because accessory widgets are composited as a
/// monochrome vibrant layer where color and gradient are discarded.
///
/// Each task row is wrapped in a `Link` to `taskflow://task/<id>` so tapping a
/// row opens the app on that task; families that allow only a single tap target
/// use `.widgetURL` for the whole widget.
struct TodayTasksWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayTasksEntry

    var body: some View {
        if let loadError = entry.loadError {
            errorLayout(loadError)
        } else {
            content
        }
    }

    /// Shown when the shared store could not be read.
    ///
    /// Deliberately distinct from the "All clear for today" empty state: the
    /// user needs to be able to tell a working widget with nothing due from a
    /// widget that cannot see their data at all.
    private func errorLayout(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .medium))
                Text("Task Flow")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Theme.orange)

            Text(message)
                .font(.system(size: family == .systemSmall ? 10 : 11))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(family == .systemSmall ? 6 : 4)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            smallLayout
        case .accessoryRectangular:
            accessoryRectangularLayout
        case .accessoryCircular:
            accessoryCircularLayout
        case .systemExtraLarge, .systemExtraLargePortrait:
            extraLargeLayout
        default:
            regularLayout
        }
    }

    /// Number of rows each family can comfortably show.
    ///
    /// `systemExtraLargePortrait` is the iOS 27 portrait-oriented extra-large
    /// family: much taller than it is wide, so it fits half again as many rows
    /// as the landscape extra large.
    private var visibleCount: Int {
        switch family {
        case .systemExtraLargePortrait: return 12
        case .systemExtraLarge:         return 8
        case .systemLarge:              return 7
        case .systemMedium:             return 3
        default:                        return 1
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "checklist")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.accent)
            Text(entry.projectName ?? "Today")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            if !entry.tasks.isEmpty {
                Text("\(entry.tasks.count)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Small

    /// Compact single-focus layout: header, then the top-priority task pinned
    /// to the bottom so the empty space reads as deliberate.
    /// The whole widget deep-links to that task via `.widgetURL`.
    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Spacer(minLength: 0)
            if let top = entry.tasks.first {
                Text(top.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                PriorityTag(priority: top.priority)
                    .padding(.top, 5)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(entry.tasks.first.flatMap { TaskDeepLink.url(for: $0.id) })
    }

    // MARK: - Medium / Large

    private var regularLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if entry.tasks.isEmpty {
                Spacer(minLength: 0)
                emptyState
                Spacer(minLength: 0)
            } else {
                ForEach(entry.tasks.prefix(visibleCount)) { task in
                    linkedRow(task)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Extra Large

    /// The extra-large family adds a per-project summary strip along the
    /// bottom, using the space the taller families cannot otherwise fill.
    private var extraLargeLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if entry.tasks.isEmpty {
                Spacer(minLength: 0)
                emptyState
                Spacer(minLength: 0)
            } else {
                ForEach(entry.tasks.prefix(visibleCount)) { task in
                    linkedRow(task)
                }
                Spacer(minLength: 0)
                if !entry.projectSummaries.isEmpty {
                    Rectangle()
                        .fill(Theme.cardBorder)
                        .frame(height: 1)
                    HStack(spacing: 10) {
                        ForEach(entry.projectSummaries) { summary in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hex: summary.colorHex))
                                    .frame(width: 7, height: 7)
                                Text("\(summary.name) · \(summary.count)")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Lock Screen

    /// Lock Screen rectangular: count plus the next task title.
    private var accessoryRectangularLayout: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "checklist")
                    .font(.system(size: 11, weight: .medium))
                Text(entry.tasks.isEmpty ? "All clear" : "\(entry.tasks.count) today")
                    .font(.system(size: 13, weight: .semibold))
            }
            if let top = entry.tasks.first {
                Text(top.title)
                    .font(.system(size: 13))
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetURL(entry.tasks.first.flatMap { TaskDeepLink.url(for: $0.id) })
    }

    /// Lock Screen circular: the count alone.
    private var accessoryCircularLayout: some View {
        VStack(spacing: -2) {
            Text("\(entry.tasks.count)")
                .font(.system(size: 20, weight: .bold))
            Text("tasks")
                .font(.system(size: 8))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(entry.tasks.first.flatMap { TaskDeepLink.url(for: $0.id) })
    }

    // MARK: - Pieces

    /// A task row wrapped in its deep link when one can be formed.
    @ViewBuilder
    private func linkedRow(_ task: TaskSnapshot) -> some View {
        if let url = TaskDeepLink.url(for: task.id) {
            Link(destination: url) { row(task) }
        } else {
            row(task)
        }
    }

    /// A single task row: project color dot, title, due time, and priority badge.
    private func row(_ task: TaskSnapshot) -> some View {
        HStack(spacing: 8) {
            projectDot(task.projectColorHex)
            Text(task.title)
                .font(.system(size: 14))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Spacer(minLength: 4)
            if let due = task.dueDate {
                Text(due, style: .time)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            PriorityTag(priority: task.priority)
        }
    }

    /// A small circular swatch of the owning project's color.
    private func projectDot(_ hex: String?) -> some View {
        Circle()
            .fill(hex.map { Color(hex: $0) } ?? Theme.accent)
            .frame(width: 7, height: 7)
    }

    private var emptyState: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle")
                .foregroundStyle(Theme.teal)
            Text("All clear for today")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

/// The wave-textured widget ground.
///
/// Two overlapping radial blooms on the near-black widget background: a large
/// accent bloom rising from the lower left and a smaller warm one from the
/// upper right. Together they suggest the app icon's wave crest without
/// redrawing it at a size where the detail would be lost.
struct WidgetWaveBackground: View {
    var body: some View {
        ZStack {
            Theme.widgetBackground

            GeometryReader { proxy in
                let size = proxy.size

                RadialGradient(
                    colors: [Theme.accent.opacity(0.28), .clear],
                    center: .init(x: 0.4, y: 0.3),
                    startRadius: 0,
                    endRadius: size.width * 0.85
                )
                .frame(width: size.width * 1.3, height: size.height * 1.2)
                .offset(x: -size.width * 0.15, y: size.height * 0.55)

                RadialGradient(
                    colors: [Theme.bloomWarm.opacity(0.14), .clear],
                    center: .init(x: 0.6, y: 0.6),
                    startRadius: 0,
                    endRadius: size.width * 0.6
                )
                .frame(width: size.width, height: size.height * 0.8)
                .offset(x: size.width * 0.2, y: -size.height * 0.4)
            }
        }
    }
}

/// A compact priority badge sized for widget rows.
///
/// Mirrors the app's `PriorityBadge` but abbreviates "Medium" to "Med" and
/// runs a size down, because a widget row is materially narrower than a task
/// card. The color mapping is shared via `Priority.color` in `Theme.swift`.
private struct PriorityTag: View {
    let priority: Priority

    /// The abbreviated label. Only `.medium` is shortened; the others already
    /// fit.
    private var label: String {
        priority == .medium ? "Med" : priority.label
    }

    var body: some View {
        if priority != .none {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(priority.color.opacity(0.85))
                .clipShape(Capsule())
        }
    }
}
