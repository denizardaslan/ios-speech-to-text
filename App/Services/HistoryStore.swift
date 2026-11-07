import Foundation

struct HistoryItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var text: String
    var date = Date()
    var source: String
}

/// Son çevirilerin listesi (cihazda, UserDefaults'ta).
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    private static let key = "history"
    private static let limit = 100

    @Published private(set) var items: [HistoryItem] = []

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([HistoryItem].self, from: data) {
            items = decoded
        }
    }

    func add(_ text: String, source: String) {
        items.insert(HistoryItem(text: text, source: source), at: 0)
        if items.count > Self.limit { items.removeLast(items.count - Self.limit) }
        save()
    }

    func delete(at offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
