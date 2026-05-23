import Foundation
import SwiftData

/// A named grouping of tasks, displayed with a custom color and SF Symbol icon.
///
/// Projects let users organise related tasks into collections.
/// Each project stores its accent color as a hex string (e.g. `"#6E56CF"`)
/// and its icon as an SF Symbol name (e.g. `"folder"`), allowing both to be
/// persisted without a custom `Codable` implementation.
///
/// - Note: `final` is required for SwiftData `@Model` classes.
@Model final class Project {
    /// Stable unique identifier. Defaults to a new UUID at creation.
    var id: UUID = UUID()

    /// The display name shown in lists and task detail views.
    var name: String

    /// The project's accent color encoded as a CSS-style hex string (e.g. `"#6E56CF"`).
    /// Converted to a SwiftUI `Color` at the call site via `Color(hex:)`.
    var colorHex: String = "#6E56CF"

    /// The SF Symbol name used to represent this project in the UI.
    var symbolName: String = "folder"

    /// The date this project was first saved to the store.
    var createdAt: Date = Date()

    /// All tasks that belong to this project.
    ///
    /// `deleteRule: .nullify` and `inverse: \Task.project` ensure that
    /// deleting a project sets each task's `project` property to `nil`
    /// rather than deleting the tasks themselves.
    @Relationship(deleteRule: .nullify, inverse: \Task.project) var tasks: [Task] = []

    /// Creates a new project with the specified display name and optional styling.
    ///
    /// - Parameters:
    ///   - name: The human-readable project name.
    ///   - colorHex: A hex color string used as the project accent; defaults to deep indigo `"#6E56CF"`.
    ///   - symbolName: An SF Symbol identifier for the project icon; defaults to `"folder"`.
    init(name: String, colorHex: String = "#6E56CF", symbolName: String = "folder") {
        self.name = name
        self.colorHex = colorHex
        self.symbolName = symbolName
    }
}
