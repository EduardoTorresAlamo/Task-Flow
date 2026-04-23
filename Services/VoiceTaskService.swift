import Speech
import AVFoundation
import Observation

@Observable @MainActor final class VoiceTaskService {
    var transcript: String = ""
    var isListening: Bool = false
    var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    private let recognizer = SFSpeechRecognizer(locale: Locale.current)
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    func requestPermission() async {
        authorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                DispatchQueue.main.async { continuation.resume(returning: status) }
            }
        }
        _ = await AVAudioApplication.requestRecordPermission()
    }

    func startListening() throws {
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        guard authorizationStatus == .authorized,
              let recognizer,
              recognizer.isAvailable else { return }

        stopListening()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let engine = AVAudioEngine()
        audioEngine = engine
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        // Capture only the request, not self, to avoid actor-crossing in the audio tap
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        engine.prepare()
        try engine.start()
        isListening = true
        transcript = ""

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if error != nil || result?.isFinal == true {
                    self.stopListening()
                }
            }
        }
    }

    func stopListening() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
