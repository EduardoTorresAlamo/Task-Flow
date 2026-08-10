import SwiftUI

/// A single row in the task list representing one `Task`.
///
/// Displays a completion toggle, the task title with optional strikethrough
/// for completed tasks, the formatted due date, and a priority badge.
/// Tapping the row (outside the toggle) fires the `onTap` callback so the
/// parent view can present `TaskEditView`.
///
/// The row also supports swipe-to-complete: dragging left reveals a green
/// "Done" backdrop, and releasing past `Theme.swipeCommitDistance` completes
/// the task. This is implemented with a drag gesture rather than
/// `.swipeActions` because the Inbox renders its groups in a `ScrollView` +
/// `LazyVStack` (to get the design's section spacing and card insets), and
/// `.swipeActions` is only available inside a `List`.
struct TaskRowView: View {
    /// The task to display. `@Bindable` enables the completion toggle to write
    /// `task.isCompleted`, `task.completedAt`, and `task.updatedAt` directly to
    /// the SwiftData store without an intermediate `@State` copy.
    @Bindable var task: Task

    /// Whether the due stamp shows the time alone.
    ///
    /// Rows inside the Today and Tomorrow sections drop the calendar date,
    /// which the section label already states.
    var showsTimeOnly: Bool = false

    /// Whether a left-swipe on this row completes the task.
    ///
    /// Disabled on the Done screen, where completion is not the available action.
    var allowsSwipeToComplete: Bool = true

    /// Whether Apple Intelligence is currently cataloging this task.
    ///
    /// Shows a pulsing sparkle in place of the priority badge, because the badge
    /// is one of the things about to change.
    var isCataloging: Bool = false

    /// Optional callback invoked when the user taps the row (not the toggle button).
    /// Defaults to `nil` so rows can be used in read-only contexts without a handler.
    var onTap: (() -> Void)? = nil

    /// Optional callback invoked when the user taps the completion toggle
    /// or completes the swipe gesture.
    ///
    /// When provided, the parent owns the completion logic (e.g. spawning the next
    /// occurrence of a recurring task through `InboxViewModel`). When `nil`, the row
    /// falls back to mutating the task's completion flags directly.
    var onToggleComplete: (() -> Void)? = nil

    /// How far the card is currently dragged, clamped to `0...` leftward.
    @State private var dragOffset: CGFloat = 0

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

    /// Time-only formatter used inside the Today and Tomorrow sections.
    private static let timeOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    /// The due stamp shown under the title, or `nil` for an undated task.
    private var dueText: String? {
        guard let due = task.dueDate else { return nil }
        let formatter = showsTimeOnly ? Self.timeOnlyFormatter : Self.dueDateFormatter
        return formatter.string(from: due)
    }

    var body: some View {
        ZStack {
            // The completion backdrop, revealed as the card slides off it.
            // Kept in the layout at all times (rather than inserted mid-drag)
            // so the card never animates against a resizing sibling.
            completionBackdrop

            card
                .offset(x: -dragOffset)
                .gesture(allowsSwipeToComplete ? swipeGesture : nil)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    // MARK: - Pieces

    /// The green "Done" panel sitting behind the card.
    ///
    /// Its opacity tracks the drag so the action fades in as the user commits
    /// to it instead of appearing at full strength on the first pixel of travel.
    private var completionBackdrop: some View {
        HStack(spacing: 6) {
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 17, weight: .bold))
            Text("Done")
                .font(.system(size: 13, weight: .bold))
        }
        .foregroundStyle(.white)
        .padding(.trailing, Theme.contentInset)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.green)
        .opacity(dragOffset > 0 ? min(1, dragOffset / 40) : 0)
    }

    /// The task card itself.
    private var card: some View {
        GlassCard {
            HStack(spacing: 12) {
                // Completion toggle button: directly mutates the @Bindable task
                // properties so the change is persisted to SwiftData immediately.
                Button(action: complete) {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(task.isCompleted ? Theme.accent : Theme.textSecondary)
                }
                .buttonStyle(.plain) // Prevents the button style from consuming the whole row tap area.

                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.tfRowTitle)
                        .foregroundStyle(Theme.text)
                        // Strikethrough is applied only when completed so the style
                        // reflects the current state without a separate Text branch.
                        .strikethrough(task.isCompleted, color: Theme.textTertiary)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        if let dueText {
                            Text(dueText)
                                .font(.tfMeta)
                                .foregroundStyle(Theme.textSecondary)
                                // The due stamp never wraps. Without this it
                                // breaks "Aug 14, 5:00 PM" across two lines to
                                // make room for the tag chips beside it, which
                                // makes the whole row grow.
                                .fixedSize()
                        }
                        // Tags come from on-device cataloging. Capped at two per
                        // row: the row is a scanning surface, and a task with
                        // four chips stops being scannable.
                        ForEach(task.tags.prefix(2), id: \.id) { tag in
                            TagChip(tag: tag)
                        }
                    }
                }

                Spacer(minLength: 4)

                if isCataloging {
                    Image(systemName: "sparkles")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.accent)
                        .symbolEffect(.pulse, isActive: true)
                        .transition(.opacity)
                } else {
                    // PriorityBadge renders nothing for .none priority, so no guard needed.
                    PriorityBadge(priority: task.priority)
                }
            }
        }
        // An opaque fill behind the card while it is being dragged, so the green
        // backdrop does not show through the translucent material.
        .background(
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .fill(Color(hex: "#0D0D10"))
                .opacity(dragOffset > 0 ? 1 : 0)
        )
        // Tap gesture on the card itself (not the toggle) opens the edit sheet.
        .onTapGesture { onTap?() }
    }

    // MARK: - Swipe

    /// Leftward drag that completes the task when released past the threshold.
    ///
    /// `minimumDistance: 12` keeps the gesture from stealing vertical scrolling;
    /// horizontal intent has to be clear before the card starts to move.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                // Only leftward travel moves the card, and it is damped past the
                // commit distance so the row resists being dragged off-screen.
                let raw = -value.translation.width
                guard raw > 0 else {
                    dragOffset = 0
                    return
                }
                dragOffset = raw <= Theme.swipeCommitDistance
                    ? raw
                    : Theme.swipeCommitDistance + (raw - Theme.swipeCommitDistance) * 0.25
            }
            .onEnded { _ in
                if dragOffset >= Theme.swipeCommitDistance {
                    // Slide the card fully away, then complete: the task leaves
                    // the @Query result, so the row is removed from the list
                    // as the animation lands.
                    withAnimation(.easeOut(duration: 0.18)) { dragOffset = 400 }
                    complete()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragOffset = 0 }
                }
            }
    }

    /// Marks the task complete through the parent's handler when one is
    /// supplied, or directly on the model when it is not.
    private func complete() {
        if let onToggleComplete {
            // Defer to the parent so recurring-task completion can spawn
            // the next occurrence rather than just flipping the flag.
            onToggleComplete()
        } else {
            task.isCompleted.toggle()
            // Record or clear the completion timestamp in sync with the flag.
            task.completedAt = task.isCompleted ? Date() : nil
            task.updatedAt = Date()
        }
    }
}
