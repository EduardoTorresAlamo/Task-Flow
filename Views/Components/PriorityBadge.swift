import SwiftUI

/// A colored capsule badge that displays a task's priority level.
///
/// Renders nothing (an empty view) when `priority` is `.none`, so callers
/// do not need to conditionally exclude the badge at the call site.
///
/// The color mapping lives on `Priority.color` in `Theme.swift` so the app and
/// the widget extension badge a given priority identically.
/// A small outlined chip naming one of a task's tags.
///
/// Tags are generated on-device by Apple Intelligence, so they are shown in a
/// quieter treatment than the priority badge: an outline in the tag's own color
/// rather than a filled capsule, which would compete with priority for
/// attention it has not earned.
struct TagChip: View {
    let tag: Tag

    var body: some View {
        Text(tag.name)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color(hex: tag.colorHex))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                Capsule().strokeBorder(Color(hex: tag.colorHex).opacity(0.45), lineWidth: 1)
            )
            .lineLimit(1)
    }
}

struct PriorityBadge: View {
    /// The priority level to display.
    let priority: Priority

    var body: some View {
        // The `.none` case intentionally produces an empty view so the
        // badge does not take up layout space when there is nothing to show.
        if priority != .none {
            Text(priority.label)
                .font(.tfBadge)
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                // Slight transparency softens the color against the dark background.
                .background(priority.color.opacity(0.85))
                .clipShape(Capsule())
        }
    }
}
