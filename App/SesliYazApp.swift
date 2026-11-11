import SwiftUI

@main
struct SesliYazApp: App {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var controller = DictationController.shared
    @StateObject private var history = HistoryStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(controller)
                .environmentObject(history)
                .onOpenURL { url in
                    // The keyboard opens "sesliyaz://session[?record=1]" when no session is active.
                    guard url.scheme == AppConfig.urlScheme, url.host == "session" else { return }
                    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                    let record = items.contains { $0.name == "record" && $0.value == "1" }
                    let host = items.first { $0.name == "host" }?.value
                    Task { await controller.handleKeyboardLaunch(startRecording: record, hostBundleID: host) }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background { controller.appDidEnterBackground() }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var controller: DictationController

    var body: some View {
        Group {
            if settings.hasAPIKey {
                MainView()
            } else {
                OnboardingView()
            }
        }
        .fullScreenCover(isPresented: $controller.quickDictationVisible) {
            QuickDictationView()
        }
        .overlay {
            if controller.keyboardHandoffVisible {
                KeyboardHandoffView()
                    .transition(.opacity)
            }
        }
    }
}
