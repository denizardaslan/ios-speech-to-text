import Foundation

enum TranscriptionStyle: String, CaseIterable, Identifiable {
    case clean
    case verbatim

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clean: return "Temiz (önerilen)"
        case .verbatim: return "Kelimesi kelimesine"
        }
    }

    var detail: String {
        switch self {
        case .clean: return "Noktalama ekler, ıı/eee gibi dolgu seslerini ve tekrarları temizler. Anlamı değiştirmez."
        case .verbatim: return "Söylediğin her şeyi olduğu gibi yazar."
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
        case .auto: return "Otomatik"
        case .turkish: return "Türkçe"
        case .english: return "İngilizce"
        }
    }
}

/// Kullanıcı ayarları. API anahtarı Keychain'de, diğerleri UserDefaults'ta tutulur.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let defaultModel = "gemini-flash-latest"
    private static let apiKeyAccount = "gemini-api-key"

    private enum Keys {
        static let model = "model"
        static let style = "style"
        static let language = "language"
        static let sessionTimeout = "sessionTimeoutMinutes"
        static let autoCopy = "autoCopy"
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

    /// Klavye oturumu bu kadar dakika kullanılmazsa mikrofon kapatılır.
    @Published var sessionTimeoutMinutes: Int {
        didSet { defaults.set(sessionTimeoutMinutes, forKey: Keys.sessionTimeout) }
    }

    /// Uygulama içinden yapılan diktelerde sonucu otomatik panoya kopyala.
    @Published var autoCopy: Bool {
        didSet { defaults.set(autoCopy, forKey: Keys.autoCopy) }
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
    }

    /// Kayıtlı ayarlarla bir çevirici oluşturur. Kestirmeler (arka planda) da bunu kullanır.
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
