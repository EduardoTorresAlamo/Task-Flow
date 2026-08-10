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
            Swift.Task {
                if voiceService.isListening {
                    // Stop first so the analyzer can flush its last volatile
                    // segment, then read the settled transcript.
                    await voiceService.stopListening()
                    let final = voiceService.transcript
                    if !final.isEmpty { onTranscript(final) }
                } else if voiceService.authorizationStatus == .notDetermined {
                    // First-time use: request permission and install the
                    // on-device model, then start in the same action so the
                    // user does not have to tap the mic a second time.
                    await voiceService.requestPermission()
                    if voiceService.authorizationStatus == .authorized, voiceService.isOnDeviceReady {
                        try? await voiceService.startListening()
                    }
                } else if voiceService.authorizationStatus == .authorized {
                    // Errors (e.g. an audio session conflict) are swallowed here;
                    // the button simply stays in its non-listening state.
                    try? await voiceService.startListening()
                }
                // .denied / .restricted are intentionally ignored: the button is
                // disabled in those states and explains itself via its label.
            }
        } label: {
            Image(systemName: voiceService.isListening ? "waveform" : "mic")
                .font(.system(size: 17))
                .foregroundStyle(iconColor)
                // .pulse effect provides a subtle visual heartbeat while audio is being captured,
                // giving the user clear feedback that recording is active.
                .symbolEffect(.pulse, isActive: voiceService.isListening)
        }
        .buttonStyle(.plain)
        // Disabled rather than silently failing when the locale has no
        // on-device speech model: the alternative the framework offers is
        // server-side recognition, which this app does not use.
        .disabled(isDisabled)
        .help(voiceService.unavailableReason ?? "Dictate a task")
        .accessibilityLabel(voiceService.unavailableReason ?? "Dictate a task")
    }

    /// The mic is unavailable whenever dictation could not run locally. The
    /// not-determined case stays enabled, because tapping it is what triggers
    /// the permission prompt.
    private var isDisabled: Bool {
        if voiceService.authorizationStatus == .notDetermined { return false }
        if voiceService.isInstallingModel { return true }
        return !voiceService.isOnDeviceReady || voiceService.authorizationStatus != .authorized
    }

    private var iconColor: Color {
        if voiceService.isListening { return Theme.accent }
        return isDisabled ? Theme.textTertiary : Theme.textSecondary
    }
}
