import SwiftUI
import SwiftData

/// The Projects tab: a two-column grid of the user's projects.
///
/// Each project is a tinted card in the project's own color, showing its icon,
/// name, and pending task count. The final cell is a dashed "New Project"
/// affordance. Tapping a project opens `ProjectDetailView`.
struct ProjectsView: View {
    @Environment(\.modelContext) private var modelContext

    /// Live-updating list of projects, oldest-first so the grid does not
    /// reshuffle every time a project is added.
    @Query(sort: \Project.createdAt, order: .forward)
    private var projects: [Project]

    /// The project being created or renamed, presented as a sheet.
    ///
    /// `nil` means no sheet; a `ProjectEditTarget` carries either an existing
    /// project or the intent to create a new one.
    @State private var editTarget: ProjectEditTarget?

    /// Two equal columns with the design's 12pt gutter.
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScreenHeader(title: "Projects")

                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                            ForEach(projects) { project in
                                NavigationLink {
                                    ProjectDetailView(project: project)
                                } label: {
                                    ProjectCard(project: project)
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Rename") { editTarget = .existing(project) }
                                    Button("Delete", role: .destructive) { delete(project) }
                                }
                            }

                            newProjectCard
                        }
                        .padding(.horizontal, Theme.contentInset)
                        .padding(.bottom, 24)
                    }
                }
                .padding(.top, 8)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .sheet(item: $editTarget) { target in
            ProjectEditView(target: target)
        }
    }

    // MARK: - Pieces

    private var newProjectCard: some View {
        Button {
            editTarget = .new
        } label: {
            VStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                Text("New Project")
                    .font(.system(size: 13))
            }
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity)
            // Matches the height of a populated card so the grid stays even.
            .frame(height: 128)
            .background(Theme.cardFill)
            .clipShape(RoundedRectangle(cornerRadius: Theme.barRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.barRadius, style: .continuous)
                    .strokeBorder(
                        Theme.cardBorder,
                        style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                    )
            )
        }
        .buttonStyle(.plain)
    }

    /// Deletes a project. Its tasks survive: `Project.tasks` uses
    /// `deleteRule: .nullify`, so they fall back to having no project.
    private func delete(_ project: Project) {
        modelContext.delete(project)
    }
}

/// One project cell in the grid.
private struct ProjectCard: View {
    let project: Project

    /// Tasks still to do in this project. Completed tasks are excluded so the
    /// number reads as remaining work rather than lifetime volume.
    private var pendingCount: Int {
        project.tasks.filter { !$0.isCompleted }.count
    }

    var body: some View {
        let color = Color(hex: project.colorHex)

        return VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Circle().fill(color)
                Image(systemName: project.symbolName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
            }
            .frame(width: 36, height: 36)

            Text(project.name)
                .font(.tfCardTitle)
                .foregroundStyle(Theme.text)
                .lineLimit(1)

            Text(pendingCount == 1 ? "1 task" : "\(pendingCount) tasks")
                .font(.tfMeta)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: 128)
        // The card is tinted with its own project color rather than the neutral
        // card fill, which is what makes the grid scannable at a glance.
        .background(color.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: Theme.barRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.barRadius, style: .continuous)
                .strokeBorder(color.opacity(0.25), lineWidth: 1)
        )
    }
}
