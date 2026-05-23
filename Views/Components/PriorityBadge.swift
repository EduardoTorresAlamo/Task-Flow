import SwiftUI

/// A colored capsule badge that displays a task's priority level.
///
/// Renders nothing (an empty view) when `priority` is `.none`, so callers
/// do not need to conditionally exclude the badge at the call site.
///
/// Color mapping:
/// - `.none`   - renders nothing
/// - `.low`    - blue
/// - `.medium` - orange
/// - `.high`   - red
struct PriorityBadge: View {
    /// The priority level to display.
    let priority: Priority

    /// The badge background color derived from the priority level.
    private var color: Color {
        switch priority {
        case .none:   return .gray
        case .low:    return .blue
        case .medium: return .orange
        case .high:   return .red
        }
    }

    var body: some View {
        // The `.none` case intentionally produces an empty view so the
        // badge does not take up layout space when there is nothing to show.
        if priority != .none {
            Text(priority.label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                // Slight transparency softens the color against the dark background.
                .background(color.opacity(0.85))
                .clipShape(Capsule())
        }
    }
}
