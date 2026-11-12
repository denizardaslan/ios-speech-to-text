import Foundation
import UIKit
import os

private let log = Logger(subsystem: "com.denizardaslan.sesliyaz", category: "Dictation")

/// Who the recording is for (where the result should be delivered).
enum RecordingOrigin {
    /// Started from the keyboard → the text is sent to the keyboard and typed at the cursor.
    case keyboard
    /// From inside the app / the "Dictate" shortcut → the text is copied to the clipboard.
    case app
}

/// The brains of the app: audio session, recording, transcription and delivering the result.
@MainActor
final class DictationController: ObservableObject {
    static let shared = DictationController()

    @Published private(set) var state: EngineState = .off
    /// Is the keyboard session on (is the microphone waiting in the background)?
    @Published private(set) var sessionActive = false
    @Published private(set) var level: Float = 0
    @Published private(set) var lastText = ""
    @Published private(set) var lastError: String?
    /// The last transcription failed but its audio was kept, so it can be sent again.
    @Published private(set) var canRetry = false
    @Published private(set) var recordingStartedAt: Date?
    /// Full-screen recording view when opened by the "Dictate" shortcut.
    @Published var quickDictationVisible = false
    /// Whether the last result was copied to the clipboard (for the badge in the UI).
    @Published private(set) var copiedToClipboard = false
    /// The keyboard opened the app: show the "listening, swipe back" screen.
    @Published var keyboardHandoffVisible = false

    private let recorder = AudioRecorder()
    private let settings = AppSettings.shared
    private let history = HistoryStore.shared

    private var origin: RecordingOrigin = .app
    private var failedAudio: (url: URL, origin: RecordingOrigin)?
    private var idleTimer: Timer?
    private var maxDurationTimer: Timer?
    private var tokens: [ObservationToken] = []

    /// A safe upper limit for sending audio inline to Gemini.
    private let maxRecordingSeconds: TimeInterval = 5 * 60

    private init() {
        recorder.onLevel = { [weak self] level in self?.level = level }
        recorder.onUnexpectedStop = { [weak self] message in
            guard let self else { return }
            self.lastError = message
            self.sessionActive = false
            self.recordingStartedAt = nil
            self.level = 0
            self.cancelTimers()
            self.publish(.off)
        }
        listenToKeyboard()
        publish(.off)
    }

    // MARK: - Keyboard commands

    private func listenToKeyboard() {
        let ipc = DarwinNotifier.shared
        tokens = [
            ipc.observe(.ping) { [weak self] in self?.publishCurrentState() },
            ipc.observe(.startRecording) { [weak self] in
                guard let self else { return }
                // iOS does not let an app turn on the mic from the background, so without a
                // session we only report "off" and the keyboard opens the app.
                guard self.sessionActive else {
                    self.lastError = nil
                    return self.publishCurrentState()
                }
                Task { await self.startRecording(origin: .keyboard) }
            },
            ipc.observe(.stopRecording) { [weak self] in self?.stopRecording() },
            ipc.observe(.cancelRecording) { [weak self] in self?.cancelRecording() },
            ipc.observe(.retryTranscription) { [weak self] in self?.retryTranscription() },
            ipc.observe(.endSession) { [weak self] in self?.endSession() },
        ]
    }

    // MARK: - Session (for the keyboard)

    /// Turns on the microphone and keeps it ready in the background. Must be called while the app is in the foreground.
    func startSession() async {
        lastError = nil
        guard await AudioRecorder.requestPermission() else {
            fail(RecorderError.permissionDenied)
            return
        }
        do {
            try recorder.startEngine()
            sessionActive = true
            if state != .recording && state != .transcribing { publish(.ready) }
            scheduleIdleTimeout()
        } catch {
            fail(error)
        }
    }

    func endSession() {
        if state == .recording { cancelRecording() }
        sessionActive = false
        cancelTimers()
        recorder.stopEngine()
        level = 0
        if state != .transcribing { publish(.off) }
    }

    // MARK: - Opened from the keyboard

    /// The keyboard opened `sesliyaz://session` because the microphone was off.
    /// Turn it on and start recording right away; the handoff screen tells the user to
    /// swipe back to the app they were typing in. They can talk the whole time.
    func handleKeyboardLaunch(startRecording shouldRecord: Bool) async {
        // No key yet: let the onboarding screen show instead.
        guard settings.hasAPIKey else { return }
        keyboardHandoffVisible = true

        await startSession()
        guard sessionActive, shouldRecord else { return } // an error is shown on the handoff screen
        await startRecording(origin: .keyboard)
    }

    /// Called when the app goes to the background: the handoff screen is no longer needed.
    func appDidEnterBackground() {
        keyboardHandoffVisible = false
    }

    // MARK: - Recording

    func toggleRecording(origin: RecordingOrigin = .app) {
        switch state {
        case .recording: stopRecording()
        case .transcribing: break
        case .off, .ready: Task { await startRecording(origin: origin) }
        }
    }

    func startRecording(origin: RecordingOrigin) async {
        guard state != .recording, state != .transcribing else { return publishCurrentState() }
        lastError = nil
        copiedToClipboard = false
        discardFailedAudio()

        guard settings.hasAPIKey else {
            fail(TranscriptionError.missingAPIKey)
            return
        }

        if !recorder.isRunning {
            guard await AudioRecorder.requestPermission() else {
                fail(RecorderError.permissionDenied)
                return
            }
            do { try recorder.startEngine() } catch {
                fail(error)
                return
            }
        }

        do {
            try recorder.beginFile()
        } catch {
            fail(error)
            return
        }

        self.origin = origin
        recordingStartedAt = Date()
        idleTimer?.invalidate()
        maxDurationTimer?.invalidate()
        maxDurationTimer = Timer.scheduledTimer(withTimeInterval: maxRecordingSeconds, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.stopRecording() }
        }
        publish(.recording)
    }

    func stopRecording() {
        guard state == .recording else { return publishCurrentState() }
        maxDurationTimer?.invalidate()

        let duration = Date().timeIntervalSince(recordingStartedAt ?? Date())
        recordingStartedAt = nil
        let fileURL = recorder.endFile()
        releaseMicrophoneIfDone()

        guard let fileURL, duration >= 0.4 else {
            if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
            finishCycle()
            return
        }

        log.notice("Recording finished: \(duration, format: .fixed(precision: 1)) s, starting transcription")
        transcribe(fileURL, for: origin)
    }

    func cancelRecording() {
        guard state == .recording else { return publishCurrentState() }
        maxDurationTimer?.invalidate()
        recordingStartedAt = nil
        if let url = recorder.endFile() { try? FileManager.default.removeItem(at: url) }
        releaseMicrophoneIfDone()
        finishCycle()
    }

    /// The microphone goes off the moment recording ends when there is no session to keep,
    /// or when the session is set to end after each dictation. That also makes the system's
    /// microphone indicator disappear right away instead of after the transcription.
    private func releaseMicrophoneIfDone() {
        if sessionActive, origin == .keyboard, settings.sessionDuration == .afterDictation {
            sessionActive = false
            idleTimer?.invalidate()
        }
        if !sessionActive {
            recorder.stopEngine()
            level = 0
        }
    }

    // MARK: - Transcription

    private func transcribe(_ fileURL: URL, for origin: RecordingOrigin) {
        publish(.transcribing)
        // Don't let the request be cut off while the app is in the background.
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "transcribe")
        Task {
            do {
                let transcriber = try AppSettings.makeTranscriber()
                let text = try await transcriber.transcribe(audioURL: fileURL, mimeType: "audio/wav")
                try? FileManager.default.removeItem(at: fileURL)
                deliver(text, to: origin)
            } catch {
                log.error("Transcription failed: \(String(describing: error), privacy: .public)")
                lastError = error.localizedDescription
                if Self.isWorthRetrying(error) {
                    failedAudio = (fileURL, origin)
                    canRetry = true
                } else {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
            finishCycle()
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
    }

    /// Sends the audio of the last failed transcription again (network hiccup, quota, timeout…).
    func retryTranscription() {
        guard state != .recording, state != .transcribing, let failed = failedAudio else {
            return publishCurrentState()
        }
        failedAudio = nil
        canRetry = false
        lastError = nil
        transcribe(failed.url, for: failed.origin)
    }

    private func discardFailedAudio() {
        if let failed = failedAudio { try? FileManager.default.removeItem(at: failed.url) }
        failedAudio = nil
        canRetry = false
    }

    private static func isWorthRetrying(_ error: Error) -> Bool {
        guard let error = error as? TranscriptionError else { return true }
        switch error {
        case .emptyResult, .audioTooShort, .missingAPIKey, .invalidAPIKey: return false
        default: return true
        }
    }

    // MARK: - "Dictate" shortcut

    func beginQuickDictation() {
        quickDictationVisible = true
        Task { await startRecording(origin: .app) }
    }

    // MARK: - Result

    private func deliver(_ text: String, to origin: RecordingOrigin) {
        lastText = text
        switch origin {
        case .keyboard:
            history.add(text, source: "Keyboard")
            SharedStore.result = KeyboardResult(id: UUID(), text: text, createdAt: Date())
            DarwinNotifier.shared.post(.resultReady)
        case .app:
            history.add(text, source: "App")
            if settings.autoCopy {
                UIPasteboard.general.string = text
                copiedToClipboard = true
            }
        }
    }

    // MARK: - State

    private func finishCycle() {
        if sessionActive {
            if recorder.isRunning {
                scheduleIdleTimeout()
            } else {
                sessionActive = false
            }
        }
        if !sessionActive, recorder.isRunning {
            recorder.stopEngine()
            level = 0
        }
        publish(sessionActive ? .ready : .off)
    }

    private func fail(_ error: Error) {
        lastError = error.localizedDescription
        publishCurrentState()
    }

    private func publishCurrentState() { publish(state) }

    /// Publishes the state to both the UI and the keyboard (App Group + Darwin notification).
    private func publish(_ newState: EngineState) {
        state = newState
        SharedStore.state = SharedSnapshot(
            engineState: newState,
            lastError: lastError,
            canRetry: canRetry,
            recordingStartedAt: recordingStartedAt,
            updatedAt: Date()
        )
        DarwinNotifier.shared.post(.stateChanged)
    }

    // MARK: - Timers

    /// Turn off the microphone if the session goes unused for a while (battery, privacy,
    /// and the microphone indicator at the top of the screen).
    private func scheduleIdleTimeout() {
        idleTimer?.invalidate()
        idleTimer = nil
        guard let interval = settings.sessionDuration.idleInterval else { return }
        idleTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.state == .ready else { return }
                self.endSession()
            }
        }
    }

    private func cancelTimers() {
        idleTimer?.invalidate()
        maxDurationTimer?.invalidate()
        idleTimer = nil
        maxDurationTimer = nil
    }
}
