import Foundation
import SwiftData

/// Identifiers shared between the main app and the Widget extension.
///
/// Both targets compile this file (see `Shared` in each target's `sources`
/// list in `project.yml`) so the App Group id and store location are defined
/// in exactly one place.
enum AppGroup {
    /// The App Group container both targets are entitled to.
    ///
    /// Must match the `com.apple.security.application-groups` value in
    /// `App/TaskFlow.entitlements` and `Widget/TaskFlowWidget.entitlements`.
    static let identifier = "group.com.eduardotorres.Task-Flow"
}

/// Factory for the SwiftData `ModelContainer` shared by the app and widget.
///
/// The store file lives inside the App Group container so the Widget process
/// can read the exact same database the app writes to. If the App Group
/// container cannot be resolved (misconfigured entitlement) the factory falls
/// back to a per-process default store so the app still launches.
enum TaskFlowContainer {
    /// The schema shared by both targets. Kept in sync with the app's registration.
    static let schema = Schema([Task.self, Project.self, Tag.self])

    /// Builds a `ModelContainer` backed by the App Group store.
    ///
    /// - Returns: A container both processes agree on. Traps only on an
    ///   unrecoverable store-creation error, matching the app's original behavior.
    static func makeShared() -> ModelContainer {
        let configuration: ModelConfiguration
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.identifier
        ) {
            let storeURL = groupURL.appending(path: "TaskFlow.store")
            configuration = ModelConfiguration(schema: schema, url: storeURL)
        } else {
            // App Group unavailable (e.g. entitlement missing): degrade to the
            // default per-app store rather than crashing at launch.
            configuration = ModelConfiguration(schema: schema)
        }

        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Failed to create shared ModelContainer: \(error)")
        }
    }
}

/// URL routing for widget → app deep links.
///
/// The widget tags each task with a `taskflow://task/<uuid>` URL; the app
/// registers the `taskflow` scheme in its `Info.plist` and decodes the id
/// back into a `UUID` when opened.
enum TaskDeepLink {
    /// The custom URL scheme registered by the main app.
    static let scheme = "taskflow"

    /// The host used for task links (`taskflow://task/...`).
    static let taskHost = "task"

    /// Builds the deep-link URL for a given task id.
    ///
    /// - Parameter id: The `Task.id` to open.
    /// - Returns: A `taskflow://task/<uuid>` URL, or `nil` if it cannot be formed.
    static func url(for id: UUID) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = taskHost
        components.path = "/\(id.uuidString)"
        return components.url
    }

    /// Parses a task id out of an incoming deep-link URL.
    ///
    /// - Parameter url: A URL delivered via `onOpenURL`.
    /// - Returns: The decoded `Task.id`, or `nil` if the URL is not a task link.
    static func taskID(from url: URL) -> UUID? {
        guard url.scheme == scheme, url.host == taskHost else { return nil }
        let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return UUID(uuidString: raw)
    }
}
