import SwiftUI
import Speech

struct VoiceInputButton: View {
    @Environment(VoiceTaskService.self) private var voiceService
    var onTranscript: (String) -> Void

    var body: some View {
        Button {
            if voiceService.isListening {
                let final = voiceService.transcript
                voiceService.stopListening()
                if !final.isEmpty { onTranscript(final) }
            } else {
                if voiceService.authorizationStatus == .notDetermined {
                    Swift.Task { await voiceService.requestPermission() }
                } else if voiceService.authorizationStatus == .authorized {
                    try? voiceService.startListening()
                }
            }
        } label: {
            Image(systemName: voiceService.isListening ? "waveform.circle.fill" : "mic.circle")
                .font(.title3)
                .foregroundStyle(voiceService.isListening ? Color(hex: "#6E56CF") : .secondary)
                .symbolEffect(.pulse, isActive: voiceService.isListening)
        }
        .buttonStyle(.plain)
    }
}
