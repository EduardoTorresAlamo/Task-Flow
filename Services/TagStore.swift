import Foundation
import SwiftData

/// The single place `Tag` rows are created and attached to tasks.
///
/// Tags arrive from Apple Intelligence as bare lowercase strings, many of which
/// repeat across tasks. Inserting a new `Tag` per occurrence would produce a
/// store full of duplicates that all render as the same chip, so every write
/// goes through `apply(_:to:in:)`, which resolves a name to the one canonical
/// row for it.
///
/// `@MainActor` because `ModelContext` is not `Sendable` and must be touched on
/// the main actor.
@MainActor
enum TagStore {

    /// Colors assigned to new tags, cycled by a hash of the name so the same
    /// tag keeps the same color across launches without storing a counter.
    private static let palette = [
        "#9184D9", "#4D8FE0", "#5FBF8F", "#F0993D", "#F0554D", "#A7A1DB"
    ]

    /// Attaches the named tags to a task, creating rows only for names that do
    /// not exist yet.
    ///
    /// Names are matched case-insensitively against existing rows, so "Dentist"
    /// from one task and "dentist" from another resolve to a single tag.
    ///
    /// - Parameters:
    ///   - names: Tag names, in any casing. Blank entries are ignored.
    ///   - task: The task to attach them to. Existing tags are preserved.
    ///   - context: The context owning both the task and the tag rows.
    static func apply(_ names: [String], to task: Task, in context: ModelContext) {
        let cleaned = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return }

        // One fetch for the whole batch rather than a fetch per name: the tag
        // table is small, and this runs on every task creation.
        let existing = (try? context.fetch(FetchDescriptor<Tag>())) ?? []
        var byLoweredName = Dictionary(
            existing.map { ($0.name.lowercased(), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for name in cleaned {
            let key = name.lowercased()
            let tag: Tag
            if let found = byLoweredName[key] {
                tag = found
            } else {
                tag = Tag(name: key, colorHex: color(for: key))
                context.insert(tag)
                byLoweredName[key] = tag
            }
            // Guard against attaching the same tag twice, which would show a
            // duplicate chip on the task.
            if !task.tags.contains(where: { $0.id == tag.id }) {
                task.tags.append(tag)
            }
        }
    }

    /// A stable color for a tag name.
    ///
    /// Uses the name's own UTF-8 bytes rather than `hashValue`, which is seeded
    /// per process and would give the same tag a different color on every launch.
    private static func color(for name: String) -> String {
        let sum = name.utf8.reduce(0) { $0 &+ Int($1) }
        return palette[sum % palette.count]
    }
}
