import ObjectiveC
import UIKit
import os

private let log = Logger(subsystem: "com.denizardaslan.sesliyaz", category: "Navigation")

/// Jumps back to the app that opened us, i.e. what tapping "◀ WhatsApp" in the top-left
/// corner does.
///
/// iOS has no public API for this. When another app opens us, UIKit stores a private
/// `UISystemNavigationAction` (the object behind that breadcrumb) in
/// `UIApplication._systemNavigationAction`. Sending it a response for its destination
/// performs the "back" navigation. Every step is checked at runtime, so on an iOS version
/// where this changes we just return `false` and the user taps ◀ themselves.
///
/// ⚠️ Private API: fine for personal / TestFlight builds, but likely to be rejected in App Store review.
enum PreviousAppNavigator {
    /// Is there a "◀ previous app" breadcrumb we can follow right now?
    static var canReturn: Bool { navigationAction() != nil }

    @discardableResult
    static func returnToPreviousApp() -> Bool {
        guard let action = navigationAction() else {
            log.notice("No system navigation action; user has to tap ◀")
            return false
        }

        let sendSelector = NSSelectorFromString("sendResponseForDestination:")
        guard action.responds(to: sendSelector), let imp = action.method(for: sendSelector) else {
            log.error("UISystemNavigationAction has no sendResponseForDestination:")
            return false
        }

        typealias SendFunction = @convention(c) (AnyObject, Selector, UInt) -> Bool
        let send = unsafeBitCast(imp, to: SendFunction.self)
        let destination = firstDestination(of: action)
        let accepted = send(action, sendSelector, destination)
        log.notice("Returning to previous app (destination \(destination)): \(accepted)")
        return accepted
    }

    // MARK: - Private

    private static func navigationAction() -> NSObject? {
        let app = UIApplication.shared
        let getter = NSSelectorFromString("_systemNavigationAction")
        if app.responds(to: getter), let action = app.perform(getter)?.takeUnretainedValue() as? NSObject {
            return action
        }
        guard let ivar = class_getInstanceVariable(UIApplication.self, "_systemNavigationAction") else {
            return nil
        }
        return object_getIvar(UIApplication.shared, ivar) as? NSObject
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
