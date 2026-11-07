import SwiftUI

@main
struct SesliYazApp: App {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var controller = DictationController.shared
    @StateObject private var history = HistoryStore.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(controller)
                .environmentObject(history)
                .onOpenURL { url in
                    // The keyboard opens "sesliyaz://session" when no session is active.
                    guard url.scheme == AppConfig.urlScheme, url.host == "session" else { return }
                    Task { await controller.startSession() }
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
    }
}
