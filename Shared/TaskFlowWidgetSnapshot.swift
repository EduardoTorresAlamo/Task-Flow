import Foundation

/// The data the widget renders, as plain `Codable` values.
///
/// **The widget deliberately does not touch SwiftData.** Opening the container
/// in the extension works, but *any* fetch — even `fetchCount` with no
/// predicate — traps inside SwiftData and kills the extension, which leaves
/// WidgetKit rendering its placeholder skeleton forever. Verified on device on
/// 2026-08-10 by tracing each step to a file.
///
/// So the app writes this snapshot to the App Group and the widget only decodes
/// it. That is the same bridge ThreadVault uses for the same reason, and it has
/// three other benefits: the extension does no I/O beyond one small file read,
/// it stays far below the widget memory limit, and the widget can never be
/// broken by a schema change it did not compile against.
struct WidgetSnapshot: Codable, Sendable {
    /// When the app last published. Not rendered; useful when debugging staleness.
    var generatedAt: Date
    /// Today's pending tasks, already sorted by priority then due time.
    var tasks: [WidgetTask]
    /// Per-project pending counts, for the extra-large family and the
    /// configuration intent's project picker.
    var projects: [WidgetProject]

    static let empty = WidgetSnapshot(generatedAt: .distantPast, tasks: [], projects: [])
}

/// One task row in the widget.
struct WidgetTask: Codable, Sendable, Identifiable, Hashable {
    var id: UUID
    var title: String
    /// `Priority.rawValue`, kept as `Int` so the snapshot format does not depend
    /// on the app's enum staying source-compatible.
    var priorityRaw: Int
    var dueDate: Date?
    var projectColorHex: String?
    /// The project this task belongs to, for filtering by the widget's intent.
    var projectID: UUID?
}

/// One project entry: its identity, colour and how much is still pending.
struct WidgetProject: Codable, Sendable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var colorHex: String
    var pendingCount: Int
}

/// Reads and writes the snapshot file in the App Group container.
///
/// Compiled into both targets: the app writes, the widget reads.
enum WidgetSnapshotStore {
    /// The snapshot location. `nil` only if the App Group is unavailable.
    static var url: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)?
            .appending(path: "widget-snapshot.json")
    }

    /// Writes the snapshot, replacing any previous one.
    ///
    /// Failures are swallowed on purpose: a widget that cannot be updated is
    /// not a reason to interrupt anything the user is doing in the app.
    static func write(_ snapshot: WidgetSnapshot) {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Reads the snapshot, or `.empty` when the app has not published one yet.
    static func read() -> WidgetSnapshot {
        guard let url, let data = try? Data(contentsOf: url) else { return .empty }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(WidgetSnapshot.self, from: data)) ?? .empty
    }
}
