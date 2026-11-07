import AppIntents
import UIKit
import UniformTypeIdentifiers

/// Errors shown by the Shortcuts app.
struct SesliYazIntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

// MARK: - The main action for Back Tap

/// Transcribes the file produced by the "Record Audio" action in Shortcuts.
///
/// Suggested shortcut (bound to Back Tap):
///   1. Record Audio  (Start: Immediately, Finish: On Tap)
///   2. Voice Type › Transcribe Audio  (Audio: Recorded Audio)
/// The app does not open; the text is copied to the clipboard, so just long-press and "Paste".
struct TranscribeAudioIntent: AppIntent {
    static var title: LocalizedStringResource = "Transcribe Audio"
    static var description = IntentDescription(
        "Transcribes an audio recording with Gemini and copies the text to the clipboard.",
        categoryName: "Dictation"
    )
    static var openAppWhenRun = false

    @Parameter(title: "Audio", supportedTypeIdentifiers: ["public.audio"])
    var audio: IntentFile

    @Parameter(title: "Copy to Clipboard", default: true)
    var copyToClipboard: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Transcribe \(\.$audio)") {
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

        // Copy the file from the shortcut to a temp folder and convert it to 16 kHz WAV.
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
            throw SesliYazIntentError(message: "Could not read the audio file: \(error.localizedDescription)")
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
            HistoryStore.shared.add(text, source: "Shortcut")
        }
        return .result(value: text)
    }
}

// MARK: - Dictate by opening the app

/// Opens the app and starts recording right away. The text is copied to the clipboard when done.
/// An alternative for those who don't want to use the "Record Audio" action.
struct DictateIntent: AppIntent {
    static var title: LocalizedStringResource = "Dictate"
    static var description = IntentDescription(
        "Opens Voice Type and starts listening right away. The text is copied to the clipboard when done.",
        categoryName: "Dictation"
    )
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DictationController.shared.beginQuickDictation()
        return .result()
    }
}

// MARK: - Start a keyboard session

struct StartKeyboardSessionIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Keyboard Session"
    static var description = IntentDescription(
        "Gets the microphone ready in the background so the Voice Type keyboard can listen instantly.",
        categoryName: "Keyboard"
    )
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await DictationController.shared.startSession()
        return .result()
    }
}

// MARK: - Siri / Spotlight shortcuts

struct SesliYazShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: DictateIntent(),
            phrases: [
                "Dictate with \(.applicationName)",
                "Start \(.applicationName)",
            ],
            shortTitle: "Dictate",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: StartKeyboardSessionIntent(),
            phrases: [
                "Start \(.applicationName) keyboard session",
            ],
            shortTitle: "Keyboard Session",
            systemImageName: "keyboard"
        )
    }
}
