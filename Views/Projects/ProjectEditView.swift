import SwiftUI
import SwiftData

/// What `ProjectEditView` was opened to do.
///
/// Modelled as an enum rather than an optional `Project` so `.sheet(item:)` can
/// present the "create" case, which has no model object to key off.
enum ProjectEditTarget: Identifiable {
    /// Create a brand-new project.
    case new
    /// Rename or restyle an existing project.
    case existing(Project)

    var id: String {
        switch self {
        case .new: return "new"
        case .existing(let project): return project.id.uuidString
        }
    }

    /// The project being edited, or `nil` when creating.
    var project: Project? {
        switch self {
        case .new: return nil
        case .existing(let project): return project
        }
    }
}

/// A sheet for creating a project or editing an existing one's name, color,
/// and icon.
///
/// Like `TaskEditView`, edits are staged locally and only committed on Save,
/// so Cancel genuinely discards.
struct ProjectEditView: View {
    /// Whether this sheet is creating or editing, and which project if editing.
    let target: ProjectEditTarget

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var draftName = ""
    @State private var draftColorHex = Theme.projectPalette[0]
    @State private var draftSymbol = "folder"
    @State private var didSeedDrafts = false

    /// The icons offered for a project. A short curated set rather than a full
    /// SF Symbols browser: the icon is decoration, and a picker with thousands
    /// of entries would dominate a three-field form.
    private let symbols = [
        "folder", "briefcase", "house", "cart", "book",
        "heart", "airplane", "figure.run", "dollarsign.circle", "paintbrush"
    ]

    private var isCreating: Bool { target.project == nil }

    /// Save is blocked on an empty name; everything else has a valid default.
    private var canSave: Bool {
        !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        nameField
                        colorField
                        iconField
                    }
                    .padding(.horizontal, Theme.contentInset)
                    .padding(.bottom, 32)
                }
            }
            .padding(.top, 12)
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: seedDrafts)
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .font(.system(size: 16.5))
                .foregroundStyle(Theme.accent)

            Spacer()

            Text(isCreating ? "New Project" : "Edit Project")
                .font(.tfSheetTitle)
                .foregroundStyle(Theme.text)

            Spacer()

            Button("Save", action: save)
                .font(.system(size: 16.5, weight: .semibold))
                .foregroundStyle(canSave ? Theme.accent : Theme.textTertiary)
                .disabled(!canSave)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
    }

    // MARK: - Fields

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(text: "Name")
            GlassCard {
                TextField("", text: $draftName, prompt: Text("Personal").foregroundColor(Theme.textTertiary))
                    .font(.tfFieldValue)
                    .foregroundStyle(Theme.text)
                    .tint(Theme.accent)
            }
        }
    }

    private var colorField: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(text: "Color")
            GlassCard {
                HStack(spacing: 12) {
                    ForEach(Theme.projectPalette, id: \.self) { hex in
                        Button {
                            draftColorHex = hex
                        } label: {
                            Circle()
                                .fill(Color(hex: hex))
                                .frame(width: 32, height: 32)
                                // The selection ring sits outside the swatch so
                                // it does not shrink the color the user is judging.
                                .overlay(
                                    Circle()
                                        .strokeBorder(Theme.text, lineWidth: 2)
                                        .padding(-4)
                                        .opacity(draftColorHex == hex ? 1 : 0)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var iconField: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(text: "Icon")
            GlassCard {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 12) {
                    ForEach(symbols, id: \.self) { symbol in
                        Button {
                            draftSymbol = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.system(size: 17))
                                .foregroundStyle(draftSymbol == symbol ? .white : Theme.textSecondary)
                                .frame(width: 40, height: 40)
                                .background {
                                    if draftSymbol == symbol {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(Color(hex: draftColorHex))
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Persistence

    private func seedDrafts() {
        guard !didSeedDrafts else { return }
        didSeedDrafts = true
        guard let project = target.project else { return }
        draftName = project.name
        draftColorHex = project.colorHex
        draftSymbol = project.symbolName
    }

    /// Commits the drafts, inserting a new project or updating the existing one.
    private func save() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        if let project = target.project {
            project.name = name
            project.colorHex = draftColorHex
            project.symbolName = draftSymbol
        } else {
            let project = Project(name: name, colorHex: draftColorHex, symbolName: draftSymbol)
            modelContext.insert(project)
        }
        dismiss()
    }
}
