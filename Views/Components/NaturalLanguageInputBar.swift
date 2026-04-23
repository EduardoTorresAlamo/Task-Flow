import SwiftUI

struct NaturalLanguageInputBar: View {
    @Bindable var viewModel: InboxViewModel

    private static let dueDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GlassCard {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundStyle(Color(hex: "#6E56CF"))
                    TextField("e.g. Meeting with Glen tomorrow at 2pm", text: $viewModel.inputText)
                        .foregroundStyle(.white)
                        .accentColor(Color(hex: "#6E56CF"))
                        .submitLabel(.done)
                        .onSubmit { Swift.Task { await viewModel.commitTask() } }
                        .onChange(of: viewModel.inputText) { viewModel.onInputChange() }
                    VoiceInputButton { transcript in
                        viewModel.inputText = transcript
                        viewModel.onInputChange()
                    }
                }
            }

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
        .animation(.easeInOut(duration: 0.2), value: viewModel.parsedPreview?.dueDate)
        .padding(.horizontal)
    }
}
