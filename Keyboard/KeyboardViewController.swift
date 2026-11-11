import SwiftUI
import UIKit

/// The Voice Type keyboard.
///
/// Apple does not give keyboard extensions microphone access, so the main app does the recording:
///   - The keyboard tells the app "start / stop" via Darwin notifications.
///   - The app writes the text to the App Group folder and says "result ready".
///   - The keyboard types the text at the cursor with `textDocumentProxy.insertText`.
/// If the app is not running (no session), the keyboard opens it via `sesliyaz://session?record=1`:
/// the app turns on the mic, starts recording and jumps straight back here.
final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private var tokens: [ObservationToken] = []
    private var hostingController: UIHostingController<KeyboardView>?

    /// If the app does not answer a command, we know it is not running.
    private var watchdog: DispatchWorkItem?
    private var pendingCommand: IPCMessage?
    private var pingWatchdog: DispatchWorkItem?
    /// The app we are typing into (e.g. net.whatsapp.WhatsApp), so the main app can jump back to it.
    private var hostBundleID: String?

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
        // The host connection is only fully set up once we are on screen.
        hostBundleID = HostAppDetector.detect(from: self).bundleID

        if hasFullAccess, SharedStore.keyboardPreferences.autoStartOnOpen {
            // Switching to this keyboard = "I want to talk": start listening without a 🎤 tap.
            // If recording is already running (e.g. we just came back from the app), the app ignores it.
            model.errorMessage = nil
            send(.startRecording, openAppIfNoReply: true)
        } else {
            checkAppAlive()
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
        model.onCancel = { [weak self] in self?.send(.cancelRecording) }
        model.onEndSession = { [weak self] in
            self?.send(.endSession)
        }
        model.onSpace = { [weak self] in self?.textDocumentProxy.insertText(" ") }
        model.onReturn = { [weak self] in self?.textDocumentProxy.insertText("\n") }
        model.onDelete = { [weak self] in self?.textDocumentProxy.deleteBackward() }
        model.onNextKeyboard = { [weak self] in self?.advanceToNextInputMode() }
        model.onOpenApp = { [weak self] in self?.openContainingApp(startRecording: false) }
    }

    private func micTapped() {
        guard hasFullAccess else {
            model.hasFullAccess = false
            return
        }
        model.errorMessage = nil

        switch model.engineState {
        case .off:
            // First make sure the app is really not running; if it is, start right away.
            send(.startRecording, openAppIfNoReply: true)
        case .ready:
            send(.startRecording, openAppIfNoReply: true)
        case .recording:
            send(.stopRecording, openAppIfNoReply: true)
        case .transcribing:
            break
        }
    }

    /// Sends a command to the app. If no state update arrives within 0.6 s, the app is not running.
    private func send(_ message: IPCMessage, openAppIfNoReply: Bool = false) {
        watchdog?.cancel()
        pendingCommand = message
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingCommand = nil
            self.model.engineState = .off
            // Only a start command should start recording in the app; a lost stop must not.
            if openAppIfNoReply { self.openContainingApp(startRecording: message == .startRecording) }
        }
        watchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        DarwinNotifier.shared.post(message)
    }

    private func checkAppAlive() {
        guard hasFullAccess else { return }
        pingWatchdog?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.model.engineState = .off }
        pingWatchdog = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        DarwinNotifier.shared.post(.ping)
    }

    /// The app reported a state → it is running. Read the state from the App Group.
    private func appDidRespond() {
        watchdog?.cancel()
        pingWatchdog?.cancel()
        let snapshot = SharedStore.state
        model.engineState = snapshot.engineState
        model.errorMessage = snapshot.lastError

        let command = pendingCommand
        pendingCommand = nil
        // The app is running but the session is off (e.g. it timed out): go to the app to turn on the microphone.
        if command == .startRecording, snapshot.engineState == .off {
            openContainingApp(startRecording: true)
        } else {
            model.needsSessionHint = false
        }
    }

    // MARK: - Insert the result

    private func insertPendingResult() {
        guard hasFullAccess, let result = SharedStore.result else { return }
        guard result.id != SharedStore.consumedResultID else { return }
        // Don't type a stale result into the wrong field.
        guard Date().timeIntervalSince(result.createdAt) < 120 else {
            SharedStore.consumedResultID = result.id
            return
        }
        SharedStore.consumedResultID = result.id

        var text = result.text
        if let before = textDocumentProxy.documentContextBeforeInput,
           let last = before.last, !last.isWhitespace,
           let first = text.first, !first.isPunctuation {
            text = " " + text
        }
        textDocumentProxy.insertText(text)
    }

    // MARK: - Open the app

    /// Keyboard extensions cannot use `UIApplication.shared.open`. We find UIApplication in the
    /// responder chain and call openURL through the Objective-C runtime.
    private func openContainingApp(startRecording: Bool) {
        model.needsSessionHint = true
        if hostBundleID == nil { hostBundleID = HostAppDetector.detect(from: self).bundleID }
        let url = AppConfig.sessionURL(startRecording: startRecording, hostBundleID: hostBundleID) as NSURL
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
        model.errorMessage = "Open the Voice Type app and tap \"Keyboard Session › Start\"."
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
