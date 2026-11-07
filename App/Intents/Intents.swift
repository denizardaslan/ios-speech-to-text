import AppIntents
import UIKit
import UniformTypeIdentifiers

/// Kestirmeler uygulamasının göstereceği hatalar.
struct SesliYazIntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

// MARK: - Arkaya dokunma için asıl eylem

/// Kestirmeler'deki "Ses Kaydet" eyleminin ürettiği dosyayı yazıya çevirir.
///
/// Önerilen kestirme (Arkaya Dokun'a bağlanır):
///   1. Ses Kaydet  (Başlangıç: Hemen, Bitiş: Dokununca)
///   2. Sesli Yaz › Sesi Yazıya Çevir  (Ses: Kaydedilen Ses)
/// Uygulama açılmaz; metin panoya kopyalanır, uzun basıp "Yapıştır" demen yeterli.
struct TranscribeAudioIntent: AppIntent {
    static var title: LocalizedStringResource = "Sesi Yazıya Çevir"
    static var description = IntentDescription(
        "Bir ses kaydını Gemini ile yazıya çevirir ve panoya kopyalar.",
        categoryName: "Dikte"
    )
    static var openAppWhenRun = false

    @Parameter(title: "Ses", supportedTypeIdentifiers: ["public.audio"])
    var audio: IntentFile

    @Parameter(title: "Panoya kopyala", default: true)
    var copyToClipboard: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$audio) yazıya çevir") {
            \.$copyToClipboard
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let transcriber: GeminiTranscriber
        do {
            transcriber = try AppSettings.makeTranscriber()
        } catch {
            throw SesliYazIntentError(message: error.localizedDescription)
        }

        // Kestirmeden gelen dosyayı geçici klasöre al ve 16 kHz WAV'a çevir.
        let ext = (audio.filename as NSString).pathExtension
        let rawURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shortcut-\(UUID().uuidString).\(ext.isEmpty ? "m4a" : ext)")
        defer { try? FileManager.default.removeItem(at: rawURL) }

        do {
            if let source = audio.fileURL {
                let accessing = source.startAccessingSecurityScopedResource()
                defer { if accessing { source.stopAccessingSecurityScopedResource() } }
                try FileManager.default.copyItem(at: source, to: rawURL)
            } else {
                try audio.data.write(to: rawURL)
            }
        } catch {
            throw SesliYazIntentError(message: "Ses dosyası okunamadı: \(error.localizedDescription)")
        }

        let text: String
        do {
            let wavURL = try AudioFileConverter.convertToWav(rawURL)
            defer { try? FileManager.default.removeItem(at: wavURL) }
            text = try await transcriber.transcribe(audioURL: wavURL, mimeType: "audio/wav")
        } catch {
            throw SesliYazIntentError(message: error.localizedDescription)
        }

        let shouldCopy = copyToClipboard
        await MainActor.run {
            if shouldCopy { UIPasteboard.general.string = text }
            HistoryStore.shared.add(text, source: "Kestirme")
        }
        return .result(value: text)
    }
}

// MARK: - Uygulamayı açarak dikte

/// Uygulamayı açar ve hemen kayda başlar. Bitince metin panoya kopyalanır.
/// "Ses Kaydet" eylemini kullanmak istemeyenler için alternatif.
struct DictateIntent: AppIntent {
    static var title: LocalizedStringResource = "Dikte Et"
    static var description = IntentDescription(
        "Sesli Yaz'ı açar ve hemen dinlemeye başlar. Bitince metin panoya kopyalanır.",
        categoryName: "Dikte"
    )
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DictationController.shared.beginQuickDictation()
        return .result()
    }
}

// MARK: - Klavye oturumunu başlat

struct StartKeyboardSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Klavye Oturumunu Başlat"
    static var description = IntentDescription(
        "Mikrofonu arka planda hazır hale getirir; Sesli Yaz klavyesi anında dinleyebilir.",
        categoryName: "Klavye"
    )
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await DictationController.shared.startSession()
        return .result()
    }
}

// MARK: - Siri / Spotlight kısayolları

struct SesliYazShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: DictateIntent(),
            phrases: [
                "\(.applicationName) ile dikte et",
                "\(.applicationName) dinle",
            ],
            shortTitle: "Dikte Et",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: StartKeyboardSessionIntent(),
            phrases: [
                "\(.applicationName) klavye oturumunu başlat",
            ],
            shortTitle: "Klavye Oturumu",
            systemImageName: "keyboard"
        )
    }
}
