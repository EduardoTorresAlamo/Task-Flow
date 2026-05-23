import SwiftUI
import Speech

/// A microphone button that drives `VoiceTaskService` and delivers the final
/// transcript to the caller via a closure.
///
/// Tapping the button when idle starts speech recognition (requesting permission
/// first if the status is `.notDetermined`). Tapping again while active stops
/// recognition and delivers the accumulated transcript string via `onTranscript`.
///
/// The button reflects live recording state through icon and color changes, plus
/// a pulsing symbol effect while listening.
struct VoiceInputButton: View {
    /// The shared voice recognition service injected by `TaskFlowApp`.
    ///
    /// `@Environment` is used instead of a constructor parameter so the same
    /// `VoiceTaskService` instance is reached regardless of how deeply nested
    /// this button appears in the view hierarchy.
    @Environment(VoiceTaskService.self) private var voiceService

    /// Closure called with the final transcribed string when the user stops recording.
    /// Not called if the transcript is empty when recording stops.
    var onTranscript: (String) -> Void

    var body: some View {
        Button {
            if voiceService.isListening {
                // Capture transcript before stopping, because stopListening() clears it.
                let final = voiceService.transcript
                voiceService.stopListening()
                if !final.isEmpty { onTranscript(final) }
            } else {
                if voiceService.authorizationStatus == .notDetermined {
                    // First-time use: request permissions asynchronously before
                    // starting recording so the OS alert is shown to the user.
                    Swift.Task { await voiceService.requestPermission() }
                } else if voiceService.authorizationStatus == .authorized {
                    // Permission already granted; start immediately.
                    // Errors (e.g. audio session conflict) are silently swallowed here;
                    // a production app should surface them to the user.
                    try? voiceService.startListening()
                }
                // .denied / .restricted states are intentionally ignored: the button
                // appears disabled by remaining in the non-listening visual state.
            }
        } label: {
            Image(systemName: voiceService.isListening ? "waveform.circle.fill" : "mic.circle")
                .font(.title3)
                .foregroundStyle(voiceService.isListening ? Color(hex: "#6E56CF") : .secondary)
                // .pulse effect provides a subtle visual heartbeat while audio is being captured,
                // giving the user clear feedback that recording is active.
                .symbolEffect(.pulse, isActive: voiceService.isListening)
        }
        .buttonStyle(.plain)
    }
}
