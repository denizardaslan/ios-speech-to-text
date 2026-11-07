import Foundation
import UIKit

/// Kaydın kimin için yapıldığı (sonucun nereye teslim edileceği).
enum RecordingOrigin {
    /// Klavyeden başlatıldı → metin klavyeye gönderilir, imlece yazılır.
    case keyboard
    /// Uygulama içinden / "Dikte Et" kestirmesinden → metin panoya kopyalanır.
    case app
}

/// Uygulamanın beyni: ses oturumu, kayıt, çeviri ve sonucu teslim etme.
@MainActor
final class DictationController: ObservableObject {
    static let shared = DictationController()

    @Published private(set) var state: EngineState = .off
    /// Klavye oturumu açık mı (mikrofon arka planda hazır bekliyor mu)?
    @Published private(set) var sessionActive = false
    @Published private(set) var level: Float = 0
    @Published private(set) var lastText = ""
    @Published private(set) var lastError: String?
    /// "Dikte Et" kestirmesi ile açıldığında tam ekran kayıt görünümü.
    @Published var quickDictationVisible = false
    /// Son sonuç panoya kopyalandı mı (arayüzde rozet için).
    @Published private(set) var copiedToClipboard = false

    private let recorder = AudioRecorder()
    private let settings = AppSettings.shared
    private let history = HistoryStore.shared

    private var origin: RecordingOrigin = .app
    private var recordingStartedAt: Date?
    private var idleTimer: Timer?
    private var maxDurationTimer: Timer?
    private var tokens: [ObservationToken] = []

    /// Gemini'ye inline gönderilebilecek güvenli üst sınır.
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

    // MARK: - Klavye komutları

    private func listenToKeyboard() {
        let ipc = DarwinNotifier.shared
        tokens = [
            ipc.observe(.ping) { [weak self] in self?.publishCurrentState() },
            ipc.observe(.startRecording) { [weak self] in
                guard let self else { return }
                // Oturum yoksa uygulama arka planda mikrofonu açamaz; klavye uygulamayı açacak.
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

    // MARK: - Oturum (klavye için)

    /// Mikrofonu açar ve arka planda hazır bekletir. Uygulama ön plandayken çağrılmalıdır.
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

    // MARK: - Kayıt

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

        Task {
            // Uygulama arka plandayken çeviri yarıda kesilmesin.
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

    // MARK: - "Dikte Et" kestirmesi

    func beginQuickDictation() {
        quickDictationVisible = true
        Task { await startRecording(origin: .app) }
    }

    // MARK: - Sonuç

    private func deliver(_ text: String, to origin: RecordingOrigin) {
        lastText = text
        switch origin {
        case .keyboard:
            history.add(text, source: "Klavye")
            SharedStore.result = KeyboardResult(id: UUID(), text: text, createdAt: Date())
            DarwinNotifier.shared.post(.resultReady)
        case .app:
            history.add(text, source: "Uygulama")
            if settings.autoCopy {
                UIPasteboard.general.string = text
                copiedToClipboard = true
            }
        }
    }

    // MARK: - Durum

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

    /// Durumu hem arayüze hem klavyeye (App Group + Darwin bildirimi) yayınlar.
    private func publish(_ newState: EngineState) {
        state = newState
        SharedStore.state = SharedSnapshot(engineState: newState, lastError: lastError, updatedAt: Date())
        DarwinNotifier.shared.post(.stateChanged)
    }

    // MARK: - Zamanlayıcılar

    /// Oturum bir süre kullanılmazsa mikrofonu kapat (pil ve gizlilik).
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
