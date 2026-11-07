import Foundation

/// State of the audio engine (shown on the keyboard).
enum EngineState: String, Codable {
    /// Session closed; microphone off.
    case off
    /// Session open; ready to listen.
    case ready
    /// Recording.
    case recording
    /// Audio sent to Gemini, waiting for the text.
    case transcribing
}

struct SharedSnapshot: Codable, Equatable {
    var engineState: EngineState = .off
    var lastError: String?
    var updatedAt: Date = .distantPast
}

/// A transcription result the app hands over to the keyboard.
struct KeyboardResult: Codable, Equatable {
    var id: UUID
    var text: String
    var createdAt: Date
}

/// Cross-process state sharing via small JSON files in the App Group folder.
/// (The keyboard needs "Full Access" to reach the App Group.)
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

    /// ID of the last result the keyboard inserted (so the same text is not inserted twice).
    static var consumedResultID: UUID? {
        get { read(UUID.self, from: consumedFile) }
        set { write(newValue, to: consumedFile) }
    }

    // MARK: - File I/O

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
