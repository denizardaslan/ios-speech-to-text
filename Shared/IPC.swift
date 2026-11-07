import Foundation

/// Klavye ⇄ ana uygulama arasındaki mesajlar.
/// Darwin bildirimleri veri taşımaz; sadece "bir şey oldu" sinyali verir.
/// Asıl veri `SharedStore` üzerinden App Group klasöründen okunur.
enum IPCMessage: String, CaseIterable {
    // Klavye → Uygulama
    case ping
    case startRecording
    case stopRecording
    case cancelRecording
    case endSession

    // Uygulama → Klavye
    case stateChanged
    case resultReady

    var notificationName: String { "\(AppConfig.appGroupID).ipc.\(rawValue)" }
}

/// Gözlem sona erdiğinde (token bırakıldığında) dinleyiciyi kaldırır.
final class ObservationToken {
    private let onCancel: () -> Void
    init(_ onCancel: @escaping () -> Void) { self.onCancel = onCancel }
    deinit { onCancel() }
}

/// Darwin (süreçler arası) bildirim merkezi için küçük bir sarmalayıcı.
/// Tüm dinleyiciler ana thread'de çağrılır.
final class DarwinNotifier {
    static let shared = DarwinNotifier()

    private var handlers: [String: [UUID: () -> Void]] = [:]
    private let center = CFNotificationCenterGetDarwinNotifyCenter()

    private init() {}

    func post(_ message: IPCMessage) {
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(message.notificationName as CFString),
            nil, nil, true
        )
    }

    /// Dönen token saklanmalıdır; bırakıldığında dinleme durur.
    func observe(_ message: IPCMessage, handler: @escaping () -> Void) -> ObservationToken {
        dispatchPrecondition(condition: .onQueue(.main))
        let name = message.notificationName
        let id = UUID()

        if handlers[name] == nil {
            handlers[name] = [:]
            CFNotificationCenterAddObserver(
                center,
                Unmanaged.passUnretained(self).toOpaque(),
                { _, observer, cfName, _, _ in
                    guard let observer, let cfName else { return }
                    let notifier = Unmanaged<DarwinNotifier>.fromOpaque(observer).takeUnretainedValue()
                    let name = cfName.rawValue as String
                    DispatchQueue.main.async { notifier.fire(name) }
                },
                name as CFString,
                nil,
                .deliverImmediately
            )
        }
        handlers[name]?[id] = handler

        return ObservationToken { [weak self] in
            DispatchQueue.main.async { self?.handlers[name]?[id] = nil }
        }
    }

    private func fire(_ name: String) {
        handlers[name]?.values.forEach { $0() }
    }
}
