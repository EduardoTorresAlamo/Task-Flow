import SwiftUI

/// The smart text input bar at the top of `SmartInboxView`.
///
/// Accepts free-form natural-language task descriptions and shows a live
/// parsed due-date pill below the field as the user types. Submitting the
/// field or tapping the voice button commits the task.
///
/// The view delegates all parsing and commit logic to `InboxViewModel` and
/// remains purely presentational: it reads view-model state and forwards
/// user actions without any business logic of its own.
struct NaturalLanguageInputBar: View {
    /// The view model that owns input state and drives the NL parser.
    ///
    /// `@Bindable` lets the view create two-way `$viewModel.inputText` bindings
    /// on an `@Observable` object without needing `@Binding` parameters.
    @Bindable var viewModel: InboxViewModel

    /// Shared, statically-allocated formatter for displaying extracted due dates.
    ///
    /// Same pattern as `TaskRowView.dueDateFormatter`: one instance shared across
    /// all renders to avoid repeated allocation.
    private static let dueDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassCard {
                HStack {
                    // Sparkles icon signals NL/AI-assisted input to the user.
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color(hex: "#6E56CF"))
                    TextField("e.g. Meeting with Glen tomorrow at 2pm", text: $viewModel.inputText)
                        .foregroundStyle(.white)
                        .accentColor(Color(hex: "#6E56CF"))
                        .submitLabel(.done)
                        // Submitting the keyboard commits the task asynchronously.
                        // Swift.Task bridges the synchronous onSubmit closure into an async call.
                        .onSubmit { Swift.Task { await viewModel.commitTask() } }
                        // Re-parse on every character change to keep the preview pill current.
                        .onChange(of: viewModel.inputText) { viewModel.onInputChange() }
                    // Voice button transcribes speech and injects the result into inputText,
                    // then triggers onInputChange so the preview updates immediately.
                    VoiceInputButton { transcript in
                        viewModel.inputText = transcript
                        viewModel.onInputChange()
                    }
                }
            }

            // Show the extracted due-date pill only when a date was parsed.
            // The .transition modifier animates the pill in/out as the parsed date appears or disappears.
            if let date = viewModel.parsedPreview?.dueDate {
                Text("Due: \(Self.dueDateFormatter.string(from: date))")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(hex: "#6E56CF").opacity(0.8))
                    .clipShape(Capsule())
                    .padding(.leading, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        // Animate the appearance/disappearance of the due-date pill
        // whenever the parsed date value changes.
        .animation(.easeInOut(duration: 0.2), value: viewModel.parsedPreview?.dueDate)
        .padding(.horizontal)
    }
}
