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
    /// Full-screen recording view when opened by the "Dictate" shortcut.
    @Published var quickDictationVisible = false
    /// Whether the last result was copied to the clipboard (for the badge in the UI).
    @Published private(set) var copiedToClipboard = false
    /// The keyboard opened the app; shows a minimal "listening" screen until we jump back.
    @Published var keyboardHandoffVisible = false
    /// Jumping back automatically did not work (or is off): the user has to tap ◀.
    @Published private(set) var needsManualReturn = false

    private let recorder = AudioRecorder()
    private let settings = AppSettings.shared
    private let history = HistoryStore.shared

    private var origin: RecordingOrigin = .app
    private var recordingStartedAt: Date?
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
                // Without a session the app cannot turn on the mic in the background; the keyboard will open the app.
                guard self.sessionActive else {
                    self.lastError = nil
                    return self.publishCurrentState()
                }
                Task { await self.startRecording(origin: .keyboard) }
            },
            ipc.observe(.stopRecording) { [weak self] in self?.stopRecording() },
            ipc.observe(.cancelRecording) { [weak self] in self?.cancelRecording() },
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
        if state != .transcribing {
            recorder.stopEngine()
            publish(.off)
        }
        level = 0
    }

    // MARK: - Opened from the keyboard

    /// The keyboard opened `sesliyaz://session` because no session was running.
    /// Turn on the mic, start recording right away (if asked), then jump back to the app
    /// the user was typing in, so they can just keep talking. One tap instead of three.
    func handleKeyboardLaunch(startRecording shouldRecord: Bool) async {
        needsManualReturn = false
        // No key yet: let the onboarding screen show instead.
        guard settings.hasAPIKey else { return }
        keyboardHandoffVisible = true

        await startSession()
        guard sessionActive else { return } // the error is shown on the handoff screen

        if shouldRecord {
            await startRecording(origin: .keyboard)
            guard state == .recording else { return }
        }

        guard settings.autoReturn else {
            needsManualReturn = true
            return
        }
        // Give the audio session a moment to settle in the foreground before we leave.
        try? await Task.sleep(nanoseconds: 250_000_000)
        if !PreviousAppNavigator.returnToPreviousApp() {
            needsManualReturn = true
        }
    }

    /// Called when the app goes to the background: the handoff screen is no longer needed.
    func appDidEnterBackground() {
        keyboardHandoffVisible = false
        needsManualReturn = false
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
        let fileURL = recorder.endFile()
        if !sessionActive { recorder.stopEngine(); level = 0 }

        guard let fileURL, duration >= 0.4 else {
            if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
            finishCycle()
            return
        }

        publish(.transcribing)
        let origin = self.origin
        log.notice("Recording finished: \(duration, format: .fixed(precision: 1)) s, starting transcription")

        Task {
            // Don't let the transcription be cut off while the app is in the background.
            let bgTask = UIApplication.shared.beginBackgroundTask(withName: "transcribe")
            defer {
                try? FileManager.default.removeItem(at: fileURL)
                UIApplication.shared.endBackgroundTask(bgTask)
            }
            do {
                let transcriber = try AppSettings.makeTranscriber()
                let text = try await transcriber.transcribe(audioURL: fileURL, mimeType: "audio/wav")
                deliver(text, to: origin)
            } catch {
                log.error("Transcription failed: \(String(describing: error), privacy: .public)")
                lastError = error.localizedDescription
            }
            finishCycle()
        }
    }

    func cancelRecording() {
        guard state == .recording else { return publishCurrentState() }
        maxDurationTimer?.invalidate()
        if let url = recorder.endFile() { try? FileManager.default.removeItem(at: url) }
        if !sessionActive { recorder.stopEngine(); level = 0 }
        finishCycle()
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
        recordingStartedAt = nil
        if sessionActive {
            if !recorder.isRunning { sessionActive = false }
            scheduleIdleTimeout()
        }
        if !sessionActive, recorder.isRunning { recorder.stopEngine(); level = 0 }
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
        SharedStore.state = SharedSnapshot(engineState: newState, lastError: lastError, updatedAt: Date())
        DarwinNotifier.shared.post(.stateChanged)
    }

    // MARK: - Timers

    /// Turn off the microphone if the session goes unused for a while (battery and privacy).
    private func scheduleIdleTimeout() {
        idleTimer?.invalidate()
        let interval = TimeInterval(max(1, settings.sessionTimeoutMinutes) * 60)
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
