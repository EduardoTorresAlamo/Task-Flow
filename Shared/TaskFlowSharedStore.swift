import Foundation
import SwiftData
import os.log

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

    /// Raised when the App Group container cannot be resolved.
    ///
    /// This is fatal on purpose: silently opening a *different* per-process
    /// store means the app and widget read two separate databases, and any
    /// task written to the wrong one is invisible everywhere else — data loss
    /// with no error. Surfacing the failure lets the caller decide (the app
    /// logs it and degrades to memory; the widget shows its own error state).
    enum StoreError: Error {
        /// `FileManager` returned no container URL for `AppGroup.identifier`,
        /// which almost always means the entitlement is missing or misspelled.
        case appGroupUnavailable(identifier: String)
    }

    /// Builds a `ModelContainer` backed by the App Group store.
    ///
    /// Throws rather than trapping. The widget extension **must** be able to
    /// handle failure: a `fatalError` there does not show an error, it kills the
    /// extension, and WidgetKit then renders its placeholder skeleton forever
    /// with no indication that anything went wrong. That is exactly what
    /// happened on device on 2026-08-10.
    ///
    /// - Returns: A container both processes agree on.
    /// - Throws: Whatever `ModelContainer` throws when the store cannot be opened.
    static func makeShared() throws -> ModelContainer {
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: AppGroup.identifier
        ) else {
            // Do NOT fall back to a default per-app store here: that store lives
            // at a different path than the App Group one, so the app and widget
            // would silently diverge and the user's tasks would appear to
            // vanish. Fail loudly and let the caller handle it.
            throw StoreError.appGroupUnavailable(identifier: AppGroup.identifier)
        }
        let storeURL = groupURL.appending(path: "TaskFlow.store")
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    /// The container for the main app, with an in-memory fallback.
    ///
    /// The app cannot run without a `ModelContainer`, but crashing at launch is
    /// the worst way to report that: an in-memory store at least renders, and
    /// the failure is logged rather than silent.
    static func makeForApp() -> ModelContainer {
        do {
            return try makeShared()
        } catch {
            let logger = Logger(subsystem: "com.eduardotorres.Task-Flow", category: "Store")
            // Log the error *type*, never any user content — there is none in
            // these errors, but the rule is uniform (see PRIVACY.md).
            switch error {
            case StoreError.appGroupUnavailable(let identifier):
                // Critical: the on-disk store is unreachable, so this session
                // runs in memory and nothing the user does will persist. This
                // is a build/entitlement misconfiguration, not a runtime blip.
                logger.critical(
                    "App Group \(identifier, privacy: .public) unavailable; running in-memory, changes will NOT persist"
                )
            default:
                logger.fault(
                    "Shared store failed to open (\(String(describing: type(of: error)), privacy: .public)); falling back to memory"
                )
            }
            let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            // If even an in-memory store cannot be built there is nothing left
            // to degrade to.
            return try! ModelContainer(for: schema, configurations: fallback)
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
