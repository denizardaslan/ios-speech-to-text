import Foundation

/// Ana uygulama ile klavye eklentisinin ortak kullandığı sabitler.
enum AppConfig {
    /// App Group kimliği Info.plist'e build sırasında yazılır (project.yml → APP_GROUP_ID).
    static let appGroupID: String =
        (Bundle.main.object(forInfoDictionaryKey: "SesliYazAppGroup") as? String)
        ?? "group.com.denizardaslan.sesliyaz"

    static let urlScheme = "sesliyaz"

    /// Klavyenin, ses oturumunu başlatmak için ana uygulamayı açtığı adres.
    static let sessionURL = URL(string: "\(urlScheme)://session")!

    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }
}
