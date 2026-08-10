import AppIntents

/// A selectable project used to configure the widget's filter.
///
/// Exposed to the Widget configuration UI as an `AppEntity` so the user can
/// long-press the widget and pick a project (or "All Projects" by leaving the
/// parameter empty).
struct ProjectEntity: AppEntity {
    /// Mirrors `Project.id` so selections survive across data reloads.
    let id: UUID

    /// The project name shown in the configuration picker.
    let name: String

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Project"

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }

    static let defaultQuery = ProjectEntityQuery()
}

/// Supplies the list of projects to the widget configuration UI.
///
/// Reads the snapshot the app publishes to the App Group, not SwiftData: this
/// query runs inside the widget extension, where any SwiftData fetch traps.
/// See `WidgetSnapshot`.
struct ProjectEntityQuery: EntityQuery {
    /// Resolves previously-selected projects by id when the configuration is restored.
    func entities(for identifiers: [UUID]) async throws -> [ProjectEntity] {
        let wanted = Set(identifiers)
        return allProjects().filter { wanted.contains($0.id) }
    }

    /// Offers every project as a suggestion in the picker.
    func suggestedEntities() async throws -> [ProjectEntity] {
        allProjects()
    }

    /// Every published project, sorted by name for a stable picker order.
    private func allProjects() -> [ProjectEntity] {
        WidgetSnapshotStore.read().projects
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { ProjectEntity(id: $0.id, name: $0.name) }
    }
}

/// The widget's configuration intent: an optional project filter.
///
/// Backing the widget with a `WidgetConfigurationIntent` is what lets the user
/// edit the widget in place. Leaving `project` unset shows tasks from all projects.
struct ProjectFilterIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Filter by Project"
    static let description = IntentDescription("Show today's tasks from a specific project, or from all projects.")

    /// The project to filter by. `nil` means "All Projects".
    @Parameter(title: "Project")
    var project: ProjectEntity?

    init() {}

    init(project: ProjectEntity? = nil) {
        self.project = project
    }
}
