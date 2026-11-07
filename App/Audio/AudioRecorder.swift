import AVFoundation

enum RecorderError: LocalizedError {
    case permissionDenied
    case noInput

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Mikrofon izni yok. Ayarlar › Sesli Yaz › Mikrofon'u aç."
        case .noInput:
            return "Mikrofon kullanılamıyor."
        }
    }
}

/// AVAudioEngine tabanlı kaydedici.
///
/// Motor (mikrofon) "oturum" boyunca açık kalır; böylece uygulama arka plandayken de
/// çalışmaya devam eder ve klavyeden gelen komutla anında kayda başlanabilir.
/// Sadece `beginFile()` ile `endFile()` arasındaki ses dosyaya yazılır.
/// Çıktı: 16 kHz, mono, 16 bit WAV (konuşma için yeterli, dosya boyutu küçük).
final class AudioRecorder {
    static let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: true
    )!

    /// 0…1 arası ses seviyesi (ana thread'de çağrılır).
    var onLevel: ((Float) -> Void)?
    /// Motor beklenmedik şekilde durursa (telefon araması vb.) çağrılır.
    var onUnexpectedStop: ((String) -> Void)?

    private(set) var isRunning = false

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var file: AVAudioFile?
    private var fileURL: URL?
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let self, self.isRunning,
                  let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            self.stopEngine()
            self.onUnexpectedStop?("Ses oturumu kesildi (arama, Siri vb.).")
        })
        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            // Kulaklık takıldı/çıkarıldı: motoru yeni giriş formatıyla yeniden kur.
            guard let self, self.isRunning else { return }
            self.isRunning = false
            self.engine.inputNode.removeTap(onBus: 0)
            do { try self.startEngine() } catch {
                self.onUnexpectedStop?("Mikrofon yeniden başlatılamadı: \(error.localizedDescription)")
            }
        })
    }

    deinit { observers.forEach { NotificationCenter.default.removeObserver($0) } }

    // MARK: - İzin

    static func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: return await AVAudioApplication.requestRecordPermission()
        }
    }

    // MARK: - Motor

    func startEngine() throws {
        guard !isRunning else { return }

        let session = AVAudioSession.sharedInstance()
        // mixWithOthers: arka planda çalan müziği/podcast'i durdurmaz.
        try session.setCategory(.playAndRecord, mode: .default,
                                options: [.mixWithOthers, .defaultToSpeaker, .allowBluetoothA2DP])
        try session.setActive(true)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw RecorderError.noInput }

        lock.lock()
        converter = AVAudioConverter(from: inputFormat, to: Self.targetFormat)
        lock.unlock()

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        isRunning = true
    }

    func stopEngine() {
        _ = endFile()
        if isRunning || engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        isRunning = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Dosya

    func beginFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec-\(UUID().uuidString).wav")
        let newFile = try AVAudioFile(
            forWriting: url,
            settings: Self.targetFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )
        lock.lock()
        file = newFile
        fileURL = url
        lock.unlock()
    }

    /// Kaydı bitirir ve dosyanın adresini döner (dosya kapatılmış ve okunmaya hazırdır).
    func endFile() -> URL? {
        lock.lock()
        let url = fileURL
        file = nil // AVAudioFile serbest bırakılınca WAV başlığı yazılıp dosya kapanır.
        fileURL = nil
        lock.unlock()
        return url
    }

    // MARK: - Ses işleme (ses thread'i)

    private func process(_ buffer: AVAudioPCMBuffer) {
        reportLevel(buffer)

        lock.lock()
        defer { lock.unlock() }
        guard let file, let converter else { return }

        let ratio = Self.targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: Self.targetFormat, frameCapacity: capacity) else { return }

        var delivered = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if delivered {
                status.pointee = .noDataNow
                return nil
            }
            delivered = true
            status.pointee = .haveData
            return buffer
        }
        if error == nil, output.frameLength > 0 {
            try? file.write(from: output)
        }
    }

    private func reportLevel(_ buffer: AVAudioPCMBuffer) {
        guard let onLevel, let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count { sum += samples[i] * samples[i] }
        let rms = (sum / Float(count)).squareRoot()
        // Kabaca dB → 0…1
        let db = 20 * log10(max(rms, 0.000_01))
        let level = max(0, min(1, (db + 50) / 50))
        DispatchQueue.main.async { onLevel(level) }
    }
}

/// Kestirmeden gelen herhangi bir ses dosyasını (m4a, caf, mp3…) 16 kHz mono WAV'a çevirir.
enum AudioFileConverter {
    static func convertToWav(_ source: URL) throws -> URL {
        let input = try AVAudioFile(forReading: source)
        let target = AudioRecorder.targetFormat
        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("conv-\(UUID().uuidString).wav")
        let output = try AVAudioFile(forWriting: outURL, settings: target.settings,
                                     commonFormat: .pcmFormatInt16, interleaved: true)

        guard let converter = AVAudioConverter(from: input.processingFormat, to: target),
              let inBuffer = AVAudioPCMBuffer(pcmFormat: input.processingFormat, frameCapacity: 8192)
        else { throw RecorderError.noInput }

        var reachedEnd = false
        while true {
            guard let outBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 8192) else { break }
            var error: NSError?
            let status = converter.convert(to: outBuffer, error: &error) { _, inputStatus in
                if reachedEnd {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    try input.read(into: inBuffer)
                } catch {
                    reachedEnd = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                if inBuffer.frameLength == 0 {
                    reachedEnd = true
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                inputStatus.pointee = .haveData
                return inBuffer
            }
            if let error { throw error }
            if outBuffer.frameLength > 0 { try output.write(from: outBuffer) }
            if status == .endOfStream || status == .error { break }
        }
        return outURL
    }
}
