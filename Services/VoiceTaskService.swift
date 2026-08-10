import Speech
import AVFoundation
import Observation

/// Manages live speech-to-text using `SpeechAnalyzer` and `SpeechTranscriber`.
///
/// Call `requestPermission()` once to obtain speech and microphone access, then
/// `startListening()` / `stopListening()` to control the session.
///
/// **Transcription never leaves the device, by construction.** This uses the
/// modern Speech stack rather than `SFSpeechRecognizer`, and the difference is
/// a privacy guarantee rather than a preference: `SFSpeechRecognizer` streams
/// audio to Apple's servers unless `requiresOnDeviceRecognition` is set, so
/// staying local depends on remembering a flag. `SpeechAnalyzer` has no server
/// path at all — it runs a model that `AssetInventory` has installed locally,
/// and if that model is absent there is nothing to fall back to.
///
/// The cost of that guarantee is a first-run download: the locale's model is
/// fetched once via `AssetInventory.assetInstallationRequest(supporting:)`.
/// Until it lands, `isOnDeviceReady` is `false` and the microphone stays
/// disabled rather than quietly going over the network.
///
/// Confined to `@MainActor` because all observable state drives SwiftUI, and
/// the transcription results are consumed in a task that hops back here.
@Observable @MainActor final class VoiceTaskService {
    /// The accumulating text from the ongoing session.
    ///
    /// Concatenates finalised segments and appends the current volatile
    /// (still-changing) segment, so the UI shows live text that settles as the
    /// analyzer commits each phrase.
    var transcript: String = ""

    /// `true` while the audio engine is running and the analyzer is active.
    var isListening: Bool = false

    /// The current speech recognition authorization status.
    var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    /// Whether the locale's on-device model is installed and ready.
    private(set) var isOnDeviceReady: Bool = false

    /// `true` while the locale's model is downloading.
    private(set) var isInstallingModel: Bool = false

    // MARK: - Private Infrastructure

    /// The transcription module. Recreated per session because it carries the
    /// locale selection and its `results` sequence is single-use.
    private var transcriber: SpeechTranscriber?

    /// The analyzer driving the transcriber.
    private var analyzer: SpeechAnalyzer?

    /// The audio graph feeding microphone buffers into the analyzer.
    private var audioEngine: AVAudioEngine?

    /// The continuation used to push audio buffers into the analyzer's input
    /// sequence from the audio tap.
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?

    /// The task consuming `transcriber.results`.
    private var resultsTask: _Concurrency.Task<Void, Never>?

    /// Text of all segments the analyzer has finalised this session.
    private var finalizedText: String = ""

    /// A user-facing explanation of why dictation is unavailable, or `nil` when
    /// it is available.
    var unavailableReason: String? {
        if authorizationStatus == .denied || authorizationStatus == .restricted {
            return "Enable Speech Recognition for Task-Flow in Settings to dictate tasks."
        }
        if isInstallingModel {
            return "Downloading the on-device speech model for this language."
        }
        if !isOnDeviceReady {
            return "On-device dictation is not available for this language. Task-Flow will not send your voice to a server, so the microphone stays off."
        }
        return nil
    }

    // MARK: - Permissions

    /// Requests speech recognition and microphone access, then ensures the
    /// locale's on-device model is installed.
    ///
    /// `SFSpeechRecognizer.requestAuthorization` remains the authorization gate
    /// even for the modern stack: the permission is per-app, not per-API.
    func requestPermission() async {
        authorizationStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                // The callback arrives on an arbitrary queue; dispatch back to main
                // before resuming the continuation to satisfy @MainActor isolation.
                DispatchQueue.main.async { continuation.resume(returning: status) }
            }
        }
        _ = await AVAudioApplication.requestRecordPermission()
        await prepareOnDeviceModel()
    }

    /// Installs the current locale's transcription model if needed, and updates
    /// `isOnDeviceReady`.
    ///
    /// Safe to call repeatedly: `.installed` short-circuits immediately.
    func prepareOnDeviceModel() async {
        let module = SpeechTranscriber(locale: .current, preset: .progressiveTranscription)

        switch await AssetInventory.status(forModules: [module]) {
        case .installed:
            isOnDeviceReady = true
            isInstallingModel = false

        case .supported, .downloading:
            // Supported but not yet local. Request the download and wait: until
            // it completes there is no on-device path, and this app has no other.
            isInstallingModel = true
            defer { isInstallingModel = false }
            do {
                if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
                    try await request.downloadAndInstall()
                }
                isOnDeviceReady = await AssetInventory.status(forModules: [module]) == .installed
            } catch {
                isOnDeviceReady = false
            }

        case .unsupported:
            isOnDeviceReady = false
            isInstallingModel = false

        @unknown default:
            isOnDeviceReady = false
            isInstallingModel = false
        }
    }

    // MARK: - Recording Lifecycle

    /// Starts a live transcription session.
    ///
    /// Configures the audio session, wires the microphone tap into the
    /// analyzer's input stream, and begins consuming results. Volatile results
    /// update `transcript` live; finalised ones are accumulated.
    ///
    /// - Throws: Any `AVAudioSession`, `AVAudioEngine`, or `SpeechAnalyzer`
    ///   error encountered during setup.
    func startListening() async throws {
        // The on-device check is part of the guard, not a preference applied
        // later: without a local model there is nothing to transcribe with.
        guard authorizationStatus == .authorized, isOnDeviceReady else { return }

        // Tear down any in-flight session before starting a fresh one.
        // Must happen BEFORE activating the audio session below, because
        // stopListening() deactivates the shared AVAudioSession.
        await stopListening()

        let audioSession = AVAudioSession.sharedInstance()
        // .record category mutes other audio; .measurement mode minimises
        // signal processing so the analyzer receives clean input.
        // .duckOthers lowers other app audio rather than silencing it entirely.
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        let module = SpeechTranscriber(locale: .current, preset: .progressiveTranscription)
        transcriber = module

        // The analyzer consumes an AsyncSequence of AnalyzerInput. An AsyncStream
        // bridges the audio tap (which runs on an AVAudioEngine thread and cannot
        // await) to that sequence.
        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation

        let engine = AVAudioEngine()
        audioEngine = engine
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Ask the analyzer what format its model actually wants, and convert to
        // it if the microphone's native format differs. Feeding the wrong format
        // produces silence rather than an error.
        let analysisFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [module],
            considering: inputFormat
        )
        let converter = analysisFormat.flatMap { AVAudioConverter(from: inputFormat, to: $0) }

        // Capture only Sendable values in the tap: the continuation, the
        // converter, and the target format. Capturing `self` would cross actor
        // boundaries from an audio thread, which Swift 6 rejects.
        // Deprecated in iOS 27 in favour of the throwing
        // `installTapOnBus:bufferSize:format:error:block:`. That replacement is
        // declared NS_REFINED_FOR_SWIFT and the AVFAudio overlay in Xcode 27
        // beta (27A5228h) ships no wrapper for it, so the only spelling
        // available from Swift is this one — the refined symbol imports as
        // `__installTap(...)`, which is not API worth depending on. Revisit when
        // a later beta exposes the throwing form; the warning is expected until
        // then.
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            guard let converted = Self.convert(buffer, using: converter, to: analysisFormat) else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }

        let speechAnalyzer = SpeechAnalyzer(modules: [module])
        analyzer = speechAnalyzer
        try await speechAnalyzer.prepareToAnalyze(in: analysisFormat)
        try await speechAnalyzer.start(inputSequence: stream)

        engine.prepare()
        try engine.start()

        finalizedText = ""
        transcript = ""
        isListening = true

        // Volatile results are provisional and replace each other; final ones
        // are appended. Tracking them separately is what makes the live text
        // settle instead of flickering between hypotheses.
        resultsTask = _Concurrency.Task { [weak self] in
            do {
                for try await result in module.results {
                    guard let self else { return }
                    let text = String(result.text.characters)
                    if result.isFinal {
                        self.finalizedText += self.finalizedText.isEmpty ? text : " \(text)"
                        self.transcript = self.finalizedText
                    } else {
                        self.transcript = self.finalizedText.isEmpty
                            ? text
                            : "\(self.finalizedText) \(text)"
                    }
                }
            } catch {
                // A failed results stream ends the session rather than leaving
                // the mic running with nothing consuming it.
                await self?.stopListening()
            }
        }
    }

    /// Stops the session and tears down all audio and analysis resources.
    ///
    /// Safe to call even when not listening. After this call `isListening` is
    /// `false` and every held reference is nil.
    func stopListening() async {
        audioEngine?.stop()
        // Remove the buffer tap before releasing the engine to avoid an assertion failure.
        audioEngine?.inputNode.removeTap(onBus: 0)
        // Close the input stream first so the analyzer sees end-of-input and
        // can flush any pending volatile segment as a final result.
        inputContinuation?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        resultsTask?.cancel()

        audioEngine = nil
        inputContinuation = nil
        analyzer = nil
        transcriber = nil
        resultsTask = nil
        isListening = false
        // Deactivate the audio session so other apps (e.g. Music) can resume their audio.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Audio Conversion

    /// Converts a microphone buffer into the analyzer's preferred format.
    ///
    /// Returns the buffer unchanged when no conversion is needed. `nonisolated`
    /// and `static` so it is callable from the audio thread without touching
    /// actor-isolated state.
    private nonisolated static func convert(
        _ buffer: AVAudioPCMBuffer,
        using converter: AVAudioConverter?,
        to format: AVAudioFormat?
    ) -> AVAudioPCMBuffer? {
        guard let converter, let format else { return buffer }

        // Size the output for the sample-rate ratio, rounding up so a
        // downsample never truncates the tail of a buffer.
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard capacity > 0,
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else {
            return nil
        }

        var consumed = false
        var conversionError: NSError?
        converter.convert(to: output, error: &conversionError) { _, status in
            // The converter may pull more than once per output buffer; supplying
            // the input only on the first pull signals that this batch is done.
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        return conversionError == nil ? output : nil
    }
}
