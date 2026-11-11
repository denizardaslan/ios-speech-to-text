import ObjectiveC
import UIKit
import os

private let log = Logger(subsystem: "com.denizardaslan.sesliyaz", category: "Navigation")

/// Jumps back to the app the user was typing in after the keyboard opened us.
///
/// iOS has no public API for "go back to the previous app", so several routes are tried in order.
/// Each one is checked at runtime; if all fail, the user taps ◀ themselves.
///   1. **URL scheme** of the host app (`whatsapp://`, `tg://`, …). Public API, most reliable,
///      but only for apps we know. Needs the host bundle ID, which the keyboard sends along.
///   2. **`LSApplicationWorkspace.openApplicationWithBundleID:`** (private), for any host app.
///   3. **`UIApplication._systemNavigationAction`** (private), the object behind the
///      "◀ WhatsApp" breadcrumb. Did not work on the user's iPhone, kept as a last resort.
///
/// ⚠️ Routes 2 and 3 are private API: fine for personal / TestFlight builds, likely rejected by App Review.
@MainActor
enum PreviousAppNavigator {
    /// Known URL schemes that simply bring the app to the front (it resumes where it was).
    private static let knownSchemes: [String: String] = [
        "net.whatsapp.WhatsApp": "whatsapp://",
        "ph.telegra.Telegraph": "tg://",
        "org.whispersystems.signal": "sgnl://",
        "com.facebook.Messenger": "fb-messenger://",
        "com.burbn.instagram": "instagram://",
        "com.atebits.Tweetie2": "twitter://",
        "com.tinyspeck.chatlyio": "slack://",
        "com.hammerandchisel.discord": "discord://",
        "com.microsoft.skype.teams": "msteams://",
        "com.google.Gmail": "googlegmail://",
        "com.microsoft.Office.Outlook": "ms-outlook://",
        "com.apple.mobilemail": "message://",
        "com.apple.mobilenotes": "mobilenotes://",
        "com.linkedin.LinkedIn": "linkedin://",
        "com.google.chrome.ios": "googlechrome://",
    ]

    /// Tries every route and returns whether one worked, plus a one-line report for diagnostics.
    static func returnToPreviousApp(hostBundleID: String?) async -> (success: Bool, report: String) {
        var steps: [String] = ["host: \(hostBundleID ?? "unknown")"]
        defer { log.notice("Jump back: \(steps.joined(separator: " · "), privacy: .public)") }

        if let hostBundleID {
            if hostBundleID == Bundle.main.bundleIdentifier {
                steps.append("host is us")
            } else {
                if let scheme = knownSchemes[hostBundleID], let url = URL(string: scheme) {
                    let opened = await UIApplication.shared.open(url)
                    steps.append("scheme \(scheme) \(opened ? "✓" : "✗")")
                    if opened { return (true, steps.joined(separator: " · ")) }
                }
                let launched = openWithWorkspace(bundleID: hostBundleID)
                steps.append("workspace \(launched ? "✓" : "✗")")
                if launched { return (true, steps.joined(separator: " · ")) }
            }
        }

        let breadcrumb = followBreadcrumb()
        steps.append("breadcrumb \(breadcrumb)")
        return (breadcrumb == "✓", steps.joined(separator: " · "))
    }

    // MARK: - Route 2: LSApplicationWorkspace (private)

    private static func openWithWorkspace(bundleID: String) -> Bool {
        guard let workspaceClass = NSClassFromString("LSApplicationWorkspace") else { return false }
        let classObject = workspaceClass as AnyObject
        let defaultWorkspace = NSSelectorFromString("defaultWorkspace")
        guard classObject.responds(to: defaultWorkspace),
              let workspace = classObject.perform(defaultWorkspace)?.takeUnretainedValue() as? NSObject else {
            return false
        }
        let openSelector = NSSelectorFromString("openApplicationWithBundleID:")
        guard workspace.responds(to: openSelector), let imp = workspace.method(for: openSelector) else { return false }
        typealias OpenFunction = @convention(c) (AnyObject, Selector, NSString) -> Bool
        let open = unsafeBitCast(imp, to: OpenFunction.self)
        return open(workspace, openSelector, bundleID as NSString)
    }

    // MARK: - Route 3: "◀ App" breadcrumb (private)

    private static func followBreadcrumb() -> String {
        guard let action = navigationAction() else { return "✗ (none)" }
        let sendSelector = NSSelectorFromString("sendResponseForDestination:")
        guard action.responds(to: sendSelector), let imp = action.method(for: sendSelector) else {
            return "✗ (no method)"
        }
        typealias SendFunction = @convention(c) (AnyObject, Selector, UInt) -> Bool
        let send = unsafeBitCast(imp, to: SendFunction.self)
        return send(action, sendSelector, firstDestination(of: action)) ? "✓" : "✗ (refused)"
    }

    private static func navigationAction() -> NSObject? {
        let app = UIApplication.shared
        let getter = NSSelectorFromString("_systemNavigationAction")
        if app.responds(to: getter), let action = app.perform(getter)?.takeUnretainedValue() as? NSObject {
            return action
        }
        guard let ivar = class_getInstanceVariable(UIApplication.self, "_systemNavigationAction") else {
            return nil
        }
        return object_getIvar(app, ivar) as? NSObject
    }

    /// `destinations` is an array of NSNumber; 0 (the previous app) is the usual value.
    private static func firstDestination(of action: NSObject) -> UInt {
        let selector = NSSelectorFromString("destinations")
        guard action.responds(to: selector),
              let destinations = action.value(forKey: "destinations") as? [NSNumber],
              let first = destinations.first else { return 0 }
        return first.uintValue
    }
}
