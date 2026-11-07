import Foundation

/// Messages between the keyboard and the main app.
/// Darwin notifications carry no payload; they only signal "something happened".
/// The actual data is read from the App Group folder via `SharedStore`.
enum IPCMessage: String, CaseIterable {
    // Keyboard → App
    case ping
    case startRecording
    case stopRecording
    case cancelRecording
    case endSession

    // App → Keyboard
    case stateChanged
    case resultReady

    var notificationName: String { "\(AppConfig.appGroupID).ipc.\(rawValue)" }
}

/// Removes the listener when the observation ends (the token is released).
final class ObservationToken {
    private let onCancel: () -> Void
    init(_ onCancel: @escaping () -> Void) { self.onCancel = onCancel }
    deinit { onCancel() }
}

/// A small wrapper around the Darwin (cross-process) notification center.
/// All handlers are called on the main thread.
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

    /// Keep the returned token; listening stops when it is released.
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
