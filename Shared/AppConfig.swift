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
    static func sessionURL(startRecording: Bool) -> URL {
        URL(string: "\(urlScheme)://session\(startRecording ? "?record=1" : "")")!
    }

    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }
}
