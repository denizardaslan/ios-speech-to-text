import Foundation

enum TranscriptionStyle: String, CaseIterable, Identifiable {
    case clean
    case verbatim

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clean: return "Clean (recommended)"
        case .verbatim: return "Verbatim"
        }
    }

    var detail: String {
        switch self {
        case .clean: return "Adds punctuation and removes filler sounds (um, uh) and repetitions. Does not change the meaning."
        case .verbatim: return "Writes down everything exactly as you said it."
        }
    }
}

enum DictationLanguage: String, CaseIterable, Identifiable {
    case auto
    case turkish = "tr"
    case english = "en"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .auto: return "Automatic"
        case .turkish: return "Turkish"
        case .english: return "English"
        }
    }
}

/// User settings. The API key lives in the Keychain, everything else in UserDefaults.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let defaultModel = "gemini-3.5-transcribe"
    private static let apiKeyAccount = "gemini-api-key"

    private enum Keys {
        static let model = "model"
        static let style = "style"
        static let language = "language"
        static let sessionTimeout = "sessionTimeoutMinutes"
        static let autoCopy = "autoCopy"
        static let autoReturn = "autoReturn"
    }

    private let defaults = UserDefaults.standard

    @Published var apiKey: String {
        didSet {
            let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            KeychainStore.set(trimmed.isEmpty ? nil : trimmed, for: Self.apiKeyAccount)
        }
    }

    @Published var model: String {
        didSet { defaults.set(model, forKey: Keys.model) }
    }

    @Published var style: TranscriptionStyle {
        didSet { defaults.set(style.rawValue, forKey: Keys.style) }
    }

    @Published var language: DictationLanguage {
        didSet { defaults.set(language.rawValue, forKey: Keys.language) }
    }

    /// The microphone is turned off after the keyboard session is unused for this many minutes.
    @Published var sessionTimeoutMinutes: Int {
        didSet { defaults.set(sessionTimeoutMinutes, forKey: Keys.sessionTimeout) }
    }

    /// Automatically copy the result of in-app dictation to the clipboard.
    @Published var autoCopy: Bool {
        didSet { defaults.set(autoCopy, forKey: Keys.autoCopy) }
    }

    /// When the keyboard opens the app, jump straight back to the previous app once recording has started.
    @Published var autoReturn: Bool {
        didSet { defaults.set(autoReturn, forKey: Keys.autoReturn) }
    }

    var hasAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private init() {
        apiKey = KeychainStore.string(for: Self.apiKeyAccount) ?? ""
        model = defaults.string(forKey: Keys.model) ?? Self.defaultModel
        style = TranscriptionStyle(rawValue: defaults.string(forKey: Keys.style) ?? "") ?? .clean
        language = DictationLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .auto
        let timeout = defaults.integer(forKey: Keys.sessionTimeout)
        sessionTimeoutMinutes = timeout > 0 ? timeout : 5
        autoCopy = defaults.object(forKey: Keys.autoCopy) as? Bool ?? true
        autoReturn = defaults.object(forKey: Keys.autoReturn) as? Bool ?? true
    }

    /// Creates a transcriber with the saved settings. Shortcuts (in the background) use this too.
    static func makeTranscriber() throws -> GeminiTranscriber {
        let defaults = UserDefaults.standard
        guard let key = KeychainStore.string(for: apiKeyAccount), !key.isEmpty else {
            throw TranscriptionError.missingAPIKey
        }
        let model = defaults.string(forKey: Keys.model) ?? defaultModel
        let style = TranscriptionStyle(rawValue: defaults.string(forKey: Keys.style) ?? "") ?? .clean
        let language = DictationLanguage(rawValue: defaults.string(forKey: Keys.language) ?? "") ?? .auto
        return GeminiTranscriber(apiKey: key, model: model, style: style, language: language)
    }
}
