import SwiftUI

/// A reusable card container with a frosted-glass background.
///
/// Wraps arbitrary content in a rounded rectangle with `ultraThinMaterial`
/// fill, a continuous corner radius, and a subtle drop shadow. Used throughout
/// the app to give task rows and input bars visual depth on the pure-black background.
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
    /// The view content to display inside the card.
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding()
            // ultraThinMaterial adapts to dark/light mode automatically and
            // provides the frosted-glass blur without a manual `blur` modifier.
            .background(.ultraThinMaterial)
            // .continuous style produces smoother corner transitions ("squircle" shape)
            // consistent with the iOS system UI aesthetic.
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
    }
}
