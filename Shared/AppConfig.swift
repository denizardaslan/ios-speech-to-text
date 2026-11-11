import Foundation

/// Constants shared by the main app and the keyboard extension.
enum AppConfig {
    /// The App Group ID is written into Info.plist at build time (project.yml → APP_GROUP_ID).
    static let appGroupID: String =
        (Bundle.main.object(forInfoDictionaryKey: "SesliYazAppGroup") as? String)
        ?? "group.com.denizardaslan.sesliyaz"

    static let urlScheme = "sesliyaz"

    /// The URL the keyboard opens to launch the main app and start an audio session.
    /// With `startRecording`, the app also starts recording right away (for the keyboard).
    /// `hostBundleID` is the app the keyboard is typing into, so the app can jump back to it.
    static func sessionURL(startRecording: Bool, hostBundleID: String? = nil) -> URL {
        var components = URLComponents()
        components.scheme = urlScheme
        components.host = "session"
        var items: [URLQueryItem] = []
        if startRecording { items.append(URLQueryItem(name: "record", value: "1")) }
        if let hostBundleID { items.append(URLQueryItem(name: "host", value: hostBundleID)) }
        components.queryItems = items.isEmpty ? nil : items
        return components.url!
    }

    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }
}
