import Foundation
import SwiftData

/// A color-coded label that can be applied to any number of tasks.
///
/// Tags provide a lightweight, cross-project classification system.
/// The many-to-many relationship between `Tag` and `Task` is managed
/// by SwiftData through the `inverse` parameter on `Task.tags`.
///
/// - Note: `final` is required for SwiftData `@Model` classes.
@Model final class Tag {
    /// Stable unique identifier. Defaults to a new UUID at creation.
    var id: UUID = UUID()

    /// The short label text displayed in badges and filter chips.
    var name: String

    /// The tag's badge color encoded as a hex string (e.g. `"#FF6B6B"`).
    /// Converted to a SwiftUI `Color` at call sites via `Color(hex:)`.
    var colorHex: String = "#FF6B6B"

    /// All tasks that carry this tag.
    ///
    /// The `inverse` annotation tells SwiftData that `Task.tags` is the
    /// other side of this relationship, enabling correct cascade behavior
    /// and preventing duplicate join table entries.
    @Relationship(inverse: \Task.tags) var tasks: [Task] = []

    /// Creates a new tag with the specified name and optional color.
    ///
    /// - Parameters:
    ///   - name: The display label for the tag.
    ///   - colorHex: A hex color string for the badge; defaults to coral red `"#FF6B6B"`.
    init(name: String, colorHex: String = "#FF6B6B") {
        self.name = name
        self.colorHex = colorHex
    }
}
