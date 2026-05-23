import SwiftUI

extension Color {
    /// Creates a `Color` from a CSS-style hex string.
    ///
    /// Supports 6-character strings with or without a leading `#`.
    /// Any other format silently falls back to black.
    ///
    /// - Parameter hex: A color string such as `"#6E56CF"` or `"6E56CF"`.
    ///
    /// - Note: Hex values are stored as `String` on model types so they can
    ///   be persisted by SwiftData without a custom `ValueTransformer`.
    init(hex: String) {
        // Strip any non-alphanumeric prefix/suffix (e.g. the leading "#").
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b: UInt64
        switch hex.count {
        case 6:
            // Standard 6-digit hex: RRGGBB
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            // Unsupported format; default to opaque black.
            (r, g, b) = (0, 0, 0)
        }

        // Normalise each 8-bit channel to the 0.0-1.0 range expected by SwiftUI.
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }
}
