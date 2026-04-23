import SwiftUI

struct PriorityBadge: View {
    let priority: Priority

    private var color: Color {
        switch priority {
        case .none: return .gray
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        }
    }

    var body: some View {
        if priority != .none {
            Text(priority.label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color.opacity(0.85))
                .clipShape(Capsule())
        }
    }
}
