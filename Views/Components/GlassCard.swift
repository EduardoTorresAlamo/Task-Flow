import SwiftUI

/// A reusable card container with a frosted-glass background.
///
/// Wraps arbitrary content in a rounded rectangle with `ultraThinMaterial`
/// fill, a hairline border, and a continuous corner radius. Used throughout
/// the app to give task rows, form fields, and input bars visual depth on the
/// pure-black background.
///
/// The material alone reads too dark against true black, so a faint white
/// `Theme.cardFill` is layered on top of it and the edge is drawn explicitly
/// with `Theme.cardBorder`. That three-part stack (material, tint, hairline)
/// is what produces the design's surface.
///
/// The generic `Content` parameter paired with `@ViewBuilder` allows callers to
/// pass any SwiftUI view tree, including groups and conditionals, without wrapping
/// in an explicit `Group`.
///
/// Example usage:
/// ```swift
/// GlassCard {
///     Text("Hello, Task-Flow")
/// }
/// ```
struct GlassCard<Content: View>: View {
    /// Corner radius of the card. Defaults to the task-row radius; callers that
    /// sit higher in the hierarchy (the input bar, project cards) pass
    /// `Theme.barRadius`.
    var cornerRadius: CGFloat = Theme.cardRadius

    /// Interior padding. Exposed so compact rows can tighten without having to
    /// re-implement the surface.
    var padding: CGFloat = Theme.cardPadding

    /// The view content to display inside the card.
    @ViewBuilder var content: () -> Content

    /// The card's shape, reused for the fill clip and the border stroke so the
    /// two can never drift apart.
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            // ultraThinMaterial provides the frosted blur; the white tint above
            // it lifts the surface off the true-black ground.
            .background(.ultraThinMaterial)
            .background(Theme.cardFill)
            // .continuous style produces smoother corner transitions ("squircle" shape)
            // consistent with the iOS system UI aesthetic.
            .clipShape(shape)
            .overlay(shape.strokeBorder(Theme.cardBorder, lineWidth: 1))
    }
}
