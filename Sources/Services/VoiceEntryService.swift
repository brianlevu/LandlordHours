import AVFAudio
import Foundation
import Speech

@MainActor
final class VoiceEntryService: NSObject, ObservableObject {
    static let shared = VoiceEntryService()

    @Published private(set) var isRecording = false
    @Published private(set) var transcript = ""
    @Published private(set) var errorMessage: String?
    /// Speech or microphone access was refused. Log time dims the mic and offers Settings.
    @Published private(set) var permissionDenied = false
    /// 0...1, the input level while listening (drives the mic ring; 0 in silence).
    @Published private(set) var inputLevel: Double = 0

    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private override init() {
        super.init()
    }

    func startRecording(contextualStrings: [String]) async {
        guard !isRecording else { return }

        errorMessage = nil
        transcript = ""

        guard await requestPermissions() else { return }
        guard let speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognition is not available right now."
            return
        }

        resetRecognition(cancelTask: true)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.contextualStrings = contextualStrings
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        if speechRecognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        recognitionRequest = request

        do {
            try configureAudioSession()
            try startAudioEngine(with: request)
        } catch {
            resetRecognition(cancelTask: true)
            errorMessage = "Could not start voice entry."
            return
        }

        isRecording = true
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }

                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.finishRecording()
                    }
                }

                if error != nil && self.isRecording {
                    self.errorMessage = "Voice entry stopped. Try again or type the note."
                    self.finishRecording()
                }
            }
        }
    }

    func finishRecording() {
        guard isRecording || audioEngine.isRunning else { return }

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        isRecording = false
        inputLevel = 0

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func cancelRecording() {
        resetRecognition(cancelTask: true)
        transcript = ""
        isRecording = false
    }

    /// True before the first ask: Log time shows its one-line voice intro first.
    var needsPermissionPrompt: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-LHVoiceDenied") { return false }
        if ProcessInfo.processInfo.arguments.contains("-LHVoiceFirstUse") { return true }
        #endif
        return SFSpeechRecognizer.authorizationStatus() == .notDetermined
            || AVAudioApplication.shared.recordPermission == .undetermined
    }

    /// Reads the current permission state without asking (on sheet open).
    func refreshPermissionState() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-LHVoiceDenied") { permissionDenied = true; return }
        #endif
        let speech = SFSpeechRecognizer.authorizationStatus()
        let mic = AVAudioApplication.shared.recordPermission
        permissionDenied = speech == .denied || speech == .restricted || mic == .denied
    }

    private func requestPermissions() async -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-LHVoiceDenied") {
            permissionDenied = true
            errorMessage = "Allow microphone access to dictate time entries."
            return false
        }
        #endif
        defer { refreshPermissionState() }
        let speechAllowed = await requestSpeechAuthorization()
        guard speechAllowed else {
            errorMessage = "Allow speech recognition to dictate time entries."
            return false
        }

        let microphoneAllowed = await requestMicrophoneAuthorization()
        guard microphoneAllowed else {
            errorMessage = "Allow microphone access to dictate time entries."
            return false
        }

        return true
    }

    private func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { isGranted in
                continuation.resume(returning: isGranted)
            }
        }
    }

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func startAudioEngine(with request: SFSpeechAudioBufferRecognitionRequest) throws {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            request.append(buffer)
            let level = Self.level(of: buffer)
            Task { @MainActor in self?.inputLevel = level }
        }

        audioEngine.prepare()
        try audioEngine.start()
    }

    /// RMS of the buffer mapped to 0...1 (-50 dB → 0, -10 dB → 1).
    nonisolated private static func level(of buffer: AVAudioPCMBuffer) -> Double {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) { sum += data[i] * data[i] }
        let rms = sqrt(sum / Float(buffer.frameLength))
        let db = 20 * log10(max(rms, 0.000_01))
        return Double(min(max((db + 50) / 40, 0), 1))
    }

    private func resetRecognition(cancelTask: Bool) {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        if cancelTask {
            recognitionTask?.cancel()
        }
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
