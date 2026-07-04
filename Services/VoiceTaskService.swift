import Speech
import AVFoundation
import Observation

/// Manages live speech-to-text transcription using `SFSpeechRecognizer` and `AVAudioEngine`.
///
/// Call `requestPermission()` once at app startup to obtain both speech and
/// microphone authorization. Then use `startListening()` / `stopListening()`
/// to control the recording session.
///
/// Confined to `@MainActor` because:
/// - Observable state (`transcript`, `isListening`, `authorizationStatus`) must be
///   mutated on the main actor to drive safe SwiftUI updates.
/// - `SFSpeechRecognizerAuthorizationStatus` is read/written from recognition callbacks
///   that are dispatched back to the main queue explicitly inside this class.
@Observable @MainActor final class VoiceTaskService {
    /// The accumulating text from the ongoing recognition session.
    /// Updated in real time as partial results arrive from the recognizer.
    var transcript: String = ""

    /// `true` while the audio engine is running and the recognizer is active.
    var isListening: Bool = false

    /// The current speech recognition authorization status.
    ///
    /// Starts as `.notDetermined` and is updated after `requestPermission()` resolves.
    /// The UI uses this to decide whether to show the permission prompt or start recording.
    var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    // MARK: - Private AVAudio / Speech Infrastructure

    /// The on-device speech recognizer configured to the current device locale.
    /// `nil` when speech recognition is not available in the current locale.
    private let recognizer = SFSpeechRecognizer(locale: Locale.current)

    /// The audio graph that routes microphone input into the recognition request.
    private var audioEngine: AVAudioEngine?

    /// The live-audio recognition request that accepts PCM buffers from the audio tap.
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?

    /// The running recognition task. Used to cancel and clean up when recording stops.
    private var recognitionTask: SFSpeechRecognitionTask?

    // MARK: - Permissions

    /// Requests both speech recognition and microphone access from the OS.
    ///
    /// `SFSpeechRecognizer.requestAuthorization` uses a callback; it is wrapped
    /// in `withCheckedContinuation` so the caller can `await` the result on the
    /// main actor without blocking.
    ///
    /// Microphone access is requested separately via `AVAudioApplication` (the
    /// iOS 17+ replacement for `AVCaptureDevice.requestAccess(for:)`). Both
    /// grants are required for live transcription to work.
    func requestPermission() async {
        authorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                // The callback arrives on an arbitrary queue; dispatch back to main
                // before resuming the continuation to satisfy @MainActor isolation.
                DispatchQueue.main.async { continuation.resume(returning: status) }
            }
        }
        _ = await AVAudioApplication.requestRecordPermission()
    }

    // MARK: - Recording Lifecycle

    /// Starts a live audio recognition session.
    ///
    /// Configures the `AVAudioSession` for recording, installs a tap on the
    /// input node to feed PCM buffers into the recognition request, and starts
    /// the audio engine. Partial transcription results update `transcript`
    /// in real time; the session ends automatically when the recognizer returns
    /// a final result or encounters an error.
    ///
    /// - Throws: Any `AVAudioEngine` or `AVAudioSession` error encountered
    ///   during engine preparation or activation.
    func startListening() throws {
        guard authorizationStatus == .authorized,
              let recognizer,
              recognizer.isAvailable else { return }

        // Tear down any in-flight session before starting a fresh one.
        // Must happen BEFORE activating the audio session below, because
        // stopListening() deactivates the shared AVAudioSession.
        stopListening()

        let audioSession = AVAudioSession.sharedInstance()
        // .record category mutes other audio; .measurement mode minimises
        // signal processing so the recognizer receives clean input.
        // .duckOthers lowers other app audio rather than silencing it entirely.
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        // Partial results let the UI show live transcription as the user speaks.
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let engine = AVAudioEngine()
        audioEngine = engine
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Capture only the request, not self, to avoid actor-crossing in the audio tap
        // The audio tap closure runs on an internal AVAudioEngine thread (not the main actor).
        // Capturing `self` here would require crossing actor boundaries, which is a
        // Swift 6 data-race error. Capturing `request` by weak reference is safe because
        // `request` is a class (heap object) that can be referenced from any thread.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        engine.prepare()
        try engine.start()
        isListening = true
        transcript = ""

        // The recognition callback can arrive on a background thread, so it is
        // dispatched to the main queue before touching any @MainActor state.
        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    // bestTranscription.formattedString is the highest-confidence hypothesis.
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || result?.isFinal == true {
                    self.stopListening()
                }
            }
        }
    }

    /// Stops the recording session and tears down all audio and recognition resources.
    ///
    /// Safe to call even if the engine is not currently running. After this call
    /// `isListening` is `false` and all held references to AVFoundation objects are nil.
    func stopListening() {
        audioEngine?.stop()
        // Remove the buffer tap before releasing the engine to avoid an assertion failure.
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        // Deactivate the audio session so other apps (e.g. Music) can resume their audio.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
