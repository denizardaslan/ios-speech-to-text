import Foundation

/// Ses motorunun durumu (klavyede gösterilir).
enum EngineState: String, Codable {
    /// Oturum kapalı; mikrofon kapalı.
    case off
    /// Oturum açık; konuşmaya hazır.
    case ready
    /// Kayıt yapılıyor.
    case recording
    /// Ses Gemini'ye gönderildi, metin bekleniyor.
    case transcribing
}

struct SharedSnapshot: Codable, Equatable {
    var engineState: EngineState = .off
    var lastError: String?
    var updatedAt: Date = .distantPast
}

/// Uygulamanın klavyeye teslim ettiği çeviri sonucu.
struct KeyboardResult: Codable, Equatable {
    var id: UUID
    var text: String
    var createdAt: Date
}

/// App Group klasöründe küçük JSON dosyalarıyla süreçler arası durum paylaşımı.
/// (Klavye, App Group'a erişebilmek için "Tam Erişim" izni ister.)
enum SharedStore {
    private static let stateFile = "state.json"
    private static let resultFile = "result.json"
    private static let consumedFile = "consumed.json"

    static var state: SharedSnapshot {
        get { read(SharedSnapshot.self, from: stateFile) ?? SharedSnapshot() }
        set { write(newValue, to: stateFile) }
    }

    static var result: KeyboardResult? {
        get { read(KeyboardResult.self, from: resultFile) }
        set { write(newValue, to: resultFile) }
    }

    /// Klavyenin en son eklediği sonucun kimliği (aynı metin iki kez yazılmasın diye).
    static var consumedResultID: UUID? {
        get { read(UUID.self, from: consumedFile) }
        set { write(newValue, to: consumedFile) }
    }

    // MARK: - Dosya işlemleri

    private static func url(_ name: String) -> URL? {
        AppConfig.sharedContainerURL?.appendingPathComponent(name)
    }

    private static func read<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let url = url(name), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func write<T: Encodable>(_ value: T?, to name: String) {
        guard let url = url(name) else { return }
        guard let value else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        if let data = try? JSONEncoder().encode(value) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
