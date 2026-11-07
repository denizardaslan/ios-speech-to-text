import SwiftUI
import UIKit

/// Sesli Yaz klavyesi.
///
/// Apple klavye eklentilerine mikrofon izni vermediği için kaydı ana uygulama yapar:
///   - Klavye, Darwin bildirimleriyle uygulamaya "başla / bitir" der.
///   - Uygulama metni App Group klasörüne yazar ve "sonuç hazır" der.
///   - Klavye metni `textDocumentProxy.insertText` ile imlecin olduğu yere yazar.
/// Uygulama ayakta değilse (oturum kapalı) klavye uygulamayı `sesliyaz://session` ile açar.
final class KeyboardViewController: UIInputViewController {
    private let model = KeyboardModel()
    private var tokens: [ObservationToken] = []
    private var hostingController: UIHostingController<KeyboardView>?

    /// Gönderilen komuta uygulamadan yanıt gelmezse uygulamanın ayakta olmadığını anlarız.
    private var watchdog: DispatchWorkItem?
    private var pendingCommand: IPCMessage?
    private var pingWatchdog: DispatchWorkItem?

    // MARK: - Yaşam döngüsü

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
        checkAppAlive()
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        model.showsGlobeKey = needsInputModeSwitchKey
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        model.returnKeyTitle = returnKeyTitle
    }

    // MARK: - Eylemler

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
        model.onOpenApp = { [weak self] in self?.openContainingApp() }
    }

    private func micTapped() {
        guard hasFullAccess else {
            model.hasFullAccess = false
            return
        }
        model.errorMessage = nil

        switch model.engineState {
        case .off:
            // Önce uygulamanın gerçekten kapalı olduğundan emin ol; değilse hemen başla.
            send(.startRecording, openAppIfNoReply: true)
        case .ready:
            send(.startRecording, openAppIfNoReply: true)
        case .recording:
            send(.stopRecording, openAppIfNoReply: true)
        case .transcribing:
            break
        }
    }

    /// Uygulamaya komut gönder. 0,6 sn içinde durum güncellemesi gelmezse uygulama ayakta değildir.
    private func send(_ message: IPCMessage, openAppIfNoReply: Bool = false) {
        watchdog?.cancel()
        pendingCommand = message
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingCommand = nil
            self.model.engineState = .off
            if openAppIfNoReply { self.openContainingApp() }
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

    /// Uygulama bir durum bildirdi → ayakta. Durumu App Group'tan oku.
    private func appDidRespond() {
        watchdog?.cancel()
        pingWatchdog?.cancel()
        let snapshot = SharedStore.state
        model.engineState = snapshot.engineState
        model.errorMessage = snapshot.lastError

        let command = pendingCommand
        pendingCommand = nil
        // Uygulama ayakta ama oturum kapalı (ör. süre doldu): mikrofonu açmak için uygulamaya git.
        if command == .startRecording, snapshot.engineState == .off {
            openContainingApp()
        } else {
            model.needsSessionHint = false
        }
    }

    // MARK: - Sonucu yaz

    private func insertPendingResult() {
        guard hasFullAccess, let result = SharedStore.result else { return }
        guard result.id != SharedStore.consumedResultID else { return }
        // Çok eski bir sonucu yanlış alana yazmayalım.
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

    // MARK: - Uygulamayı aç

    /// Klavye eklentileri `UIApplication.shared.open` kullanamaz. Responder zincirinde
    /// UIApplication'ı bulup openURL'ü Objective-C çalışma zamanı üzerinden çağırıyoruz.
    private func openContainingApp() {
        model.needsSessionHint = true
        let url = AppConfig.sessionURL as NSURL
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
        model.errorMessage = "Sesli Yaz uygulamasını açıp \"Klavye oturumu › Başlat\"a dokun."
    }

    private var returnKeyTitle: String {
        switch textDocumentProxy.returnKeyType ?? .default {
        case .send: return "Gönder"
        case .search, .google, .yahoo: return "Ara"
        case .go: return "Git"
        case .done: return "Bitti"
        case .next: return "Sonraki"
        default: return "Satır"
        }
    }
}
