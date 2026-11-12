import SwiftUI
import UIKit

/// The Voice Type keyboard.
///
/// Apple does not give keyboard extensions microphone access, so the main app does the recording:
///   - The keyboard tells the app "start / stop" via Darwin notifications.
///   - The app writes the text to the App Group folder and says "result ready".
///   - The keyboard types the text at the cursor with `textDocumentProxy.insertText`.
/// If the app's microphone is off, the keyboard opens the app via `sesliyaz://session?record=1`:
/// the app starts recording and asks the user to swipe back here.
final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private var tokens: [ObservationToken] = []
    private var hostingController: UIHostingController<KeyboardView>?

    /// If the app does not answer a command, we know it is not running.
    private var watchdog: DispatchWorkItem?
    private var pendingCommand: IPCMessage?
    /// Whether the pending start command may open the app when the microphone is off.
    private var pendingMayOpenApp = false
    /// The text typed by the last dictation, so it can be undone.
    private var lastInsertedText: String?

    /// The keyboard view is recreated often, so these live for the whole extension process.
    /// They keep "start when the keyboard opens" from firing right after a dictation,
    /// and from opening the app again and again if something goes wrong there.
    private static var lastBusyAt = Date.distantPast
    private static var lastAppOpenAt = Date.distantPast

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        bindActions()

        let host = UIHostingController(rootView: KeyboardView(model: model))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        let height = view.heightAnchor.constraint(equalToConstant: KeyboardView.height)
        height.priority = .defaultHigh
        height.isActive = true
        host.didMove(toParent: self)
        hostingController = host

        let ipc = DarwinNotifier.shared
        tokens = [
            ipc.observe(.stateChanged) { [weak self] in self?.appDidRespond() },
            ipc.observe(.resultReady) { [weak self] in self?.insertPendingResult() },
        ]
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        model.hasFullAccess = hasFullAccess
        model.showsGlobeKey = needsInputModeSwitchKey
        model.returnKeyTitle = returnKeyTitle
        insertPendingResult()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard hasFullAccess else { return }

        let now = Date()
        let justDictated = now.timeIntervalSince(Self.lastBusyAt) < 10
        if SharedStore.keyboardPreferences.autoStartOnOpen, !justDictated {
            // Switching to this keyboard = "I want to talk": start listening without a tap.
            // If recording is already running (we just came back from the app), the app ignores it.
            model.errorMessage = nil
            let openedRecently = now.timeIntervalSince(Self.lastAppOpenAt) < 20
            send(.startRecording, mayOpenApp: !openedRecently)
        } else {
            send(.ping)
        }
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        model.showsGlobeKey = needsInputModeSwitchKey
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        model.returnKeyTitle = returnKeyTitle
    }

    // MARK: - Actions

    private func bindActions() {
        model.onMic = { [weak self] in self?.micTapped() }
        model.onCancel = { [weak self] in
            Self.lastBusyAt = Date()
            self?.send(.cancelRecording)
        }
        model.onRetry = { [weak self] in
            self?.model.errorMessage = nil
            self?.send(.retryTranscription)
        }
        model.onUndo = { [weak self] in self?.undoLastInsert() }
        model.onEndSession = { [weak self] in self?.send(.endSession) }
        model.onSpace = { [weak self] in self?.textDocumentProxy.insertText(" ") }
        model.onReturn = { [weak self] in self?.textDocumentProxy.insertText("\n") }
        model.onDelete = { [weak self] in self?.textDocumentProxy.deleteBackward() }
        model.onNextKeyboard = { [weak self] in self?.advanceToNextInputMode() }
    }

    private func micTapped() {
        guard hasFullAccess else {
            model.hasFullAccess = false
            return
        }
        model.errorMessage = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        switch model.engineState {
        case .off, .ready:
            send(.startRecording, mayOpenApp: true)
        case .recording:
            Self.lastBusyAt = Date()
            send(.stopRecording)
        case .transcribing:
            break
        }
    }

    /// Sends a command to the app. If no state update arrives within 0.6 s, the app is not running.
    private func send(_ message: IPCMessage, mayOpenApp: Bool = false) {
        watchdog?.cancel()
        pendingCommand = message
        pendingMayOpenApp = mayOpenApp
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingCommand = nil
            self.model.apply(SharedSnapshot())
            switch message {
            case .startRecording:
                if mayOpenApp { self.openContainingApp() }
            case .stopRecording:
                self.model.errorMessage = "Voice Type stopped in the background. Tap the mic to start again."
            case .retryTranscription:
                self.model.errorMessage = "Open the Voice Type app to retry."
            default:
                break
            }
        }
        watchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        DarwinNotifier.shared.post(message)
    }

    /// The app reported a state → it is running. Read the state from the App Group.
    private func appDidRespond() {
        watchdog?.cancel()
        let snapshot = SharedStore.state
        model.apply(snapshot)
        if snapshot.engineState == .recording || snapshot.engineState == .transcribing {
            Self.lastBusyAt = Date()
        }

        let command = pendingCommand
        pendingCommand = nil
        // The app is running but its microphone is off: go there to turn it on.
        if command == .startRecording, snapshot.engineState == .off, snapshot.lastError == nil {
            if pendingMayOpenApp { openContainingApp() }
        } else {
            model.openingApp = false
        }
    }

    // MARK: - Insert the result

    private func insertPendingResult() {
        guard hasFullAccess, let result = SharedStore.result else { return }
        guard result.id != SharedStore.consumedResultID else { return }
        SharedStore.consumedResultID = result.id
        // Don't type a stale result into the wrong field.
        guard Date().timeIntervalSince(result.createdAt) < 120 else { return }

        var text = result.text
        if let before = textDocumentProxy.documentContextBeforeInput,
           let last = before.last, !last.isWhitespace,
           let first = text.first, !first.isPunctuation {
            text = " " + text
        }
        textDocumentProxy.insertText(text)
        lastInsertedText = text
        model.canUndo = true
        Self.lastBusyAt = Date()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Removes the text of the last dictation, as long as it is still right before the cursor.
    private func undoLastInsert() {
        model.canUndo = false
        guard let text = lastInsertedText else { return }
        lastInsertedText = nil
        // The proxy only exposes part of the text before the cursor, so compare the tail.
        let tail = String(text.suffix(20))
        guard let before = textDocumentProxy.documentContextBeforeInput, before.hasSuffix(tail) else { return }
        for _ in 0..<text.count { textDocumentProxy.deleteBackward() }
    }

    // MARK: - Open the app

    /// Keyboard extensions cannot use `UIApplication.shared.open`. We find UIApplication in the
    /// responder chain and call openURL through the Objective-C runtime.
    private func openContainingApp() {
        Self.lastAppOpenAt = Date()
        model.openingApp = true
        let url = AppConfig.sessionURL(startRecording: true) as NSURL
        let selector = NSSelectorFromString("openURL:options:completionHandler:")

        var responder: UIResponder? = self
        while let current = responder {
            if current is UIApplication,
               current.responds(to: selector),
               let method = current.method(for: selector) {
                typealias OpenURLFunction = @convention(c) (AnyObject, Selector, NSURL, NSDictionary, AnyObject?) -> Void
                let open = unsafeBitCast(method, to: OpenURLFunction.self)
                open(current, selector, url, NSDictionary(), nil)
                return
            }
            responder = current.next
        }
        model.openingApp = false
        model.errorMessage = "Open the Voice Type app and turn on the keyboard microphone."
    }

    private var returnKeyTitle: String {
        switch textDocumentProxy.returnKeyType ?? .default {
        case .send: return "send"
        case .search, .google, .yahoo: return "search"
        case .go: return "go"
        case .done: return "done"
        case .next: return "next"
        default: return "return"
        }
    }
}
