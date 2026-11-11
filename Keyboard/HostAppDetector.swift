import Darwin
import ObjectiveC
import UIKit

/// Finds the bundle ID of the app the keyboard is typing into (e.g. `net.whatsapp.WhatsApp`),
/// so the main app can jump straight back to it after turning on the microphone.
///
/// There is no public API for this. Two private routes are tried, each fully checked at
/// runtime so a missing class/ivar/symbol just yields `nil` instead of a crash:
///   1. `_hostBundleID` on the parent view controller (works up to iOS 15; returns "<null>" after).
///   2. iOS 16+: the host's PID → PlugInKit's `PKService` personality → its `NSXPCConnection`
///      → `xpc_connection_copy_bundle_id` (the approach used by KeyboardKit).
enum HostAppDetector {
    /// The result plus a short note about which route worked, for diagnostics.
    static func detect(from controller: UIInputViewController) -> (bundleID: String?, note: String) {
        if let id = legacyHostBundleID(controller) { return (id, "legacy") }
        switch xpcHostBundleID(controller) {
        case .success(let id): return (id, "xpc")
        case .failure(let step): return (nil, "not found (\(step))")
        }
    }

    // MARK: - Route 1

    private static func legacyHostBundleID(_ controller: UIInputViewController) -> String? {
        guard let parent = controller.parent, hasProperty(parent, "_hostBundleID"),
              let value = parent.value(forKey: "_hostBundleID") as? String,
              !value.isEmpty, value != "<null>" else { return nil }
        return value
    }

    // MARK: - Route 2

    private struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    private static func xpcHostBundleID(_ controller: UIInputViewController) -> Result<String, Failure> {
        guard let parent = controller.parent, hasProperty(parent, "_hostPID"),
              let pid = parent.value(forKey: "_hostPID") as? NSNumber else {
            return .failure(Failure("pid"))
        }

        guard let serviceClass = NSClassFromString("PKService") else { return .failure(Failure("PKService")) }
        let classObject = serviceClass as AnyObject
        let defaultService = NSSelectorFromString("defaultService")
        guard classObject.responds(to: defaultService),
              let service = classObject.perform(defaultService)?.takeUnretainedValue() as? NSObject else {
            return .failure(Failure("defaultService"))
        }

        let personalitiesSelector = NSSelectorFromString("personalities")
        guard service.responds(to: personalitiesSelector),
              let personalities = service.perform(personalitiesSelector)?.takeUnretainedValue() as? NSDictionary,
              let ownID = Bundle.main.bundleIdentifier,
              let infos = personalities.object(forKey: ownID) as? NSDictionary,
              let info = infos.object(forKey: pid) as? NSObject else {
            return .failure(Failure("personality"))
        }

        let connectionSelector = NSSelectorFromString("connection")
        guard info.responds(to: connectionSelector),
              let connection = info.perform(connectionSelector)?.takeUnretainedValue() as? NSXPCConnection,
              let ivar = class_getInstanceVariable(NSXPCConnection.self, "_xpcConnection"),
              let xpcConnection = object_getIvar(connection, ivar).map({ $0 as AnyObject }) else {
            return .failure(Failure("connection"))
        }

        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2) // RTLD_DEFAULT
        guard let symbol = dlsym(rtldDefault, "xpc_connection_copy_bundle_id") else {
            return .failure(Failure("dlsym"))
        }
        typealias CopyBundleID = @convention(c) (AnyObject) -> UnsafeMutablePointer<CChar>?
        let copyBundleID = unsafeBitCast(symbol, to: CopyBundleID.self)
        guard let cString = copyBundleID(xpcConnection) else { return .failure(Failure("bundle id")) }
        defer { free(cString) }

        let bundleID = String(cString: cString)
        return bundleID.isEmpty ? .failure(Failure("empty")) : .success(bundleID)
    }

    // MARK: - Helpers

    /// KVC on a missing key throws an Objective-C exception (a crash in Swift), so check first.
    private static func hasProperty(_ object: NSObject, _ name: String) -> Bool {
        object.responds(to: NSSelectorFromString(name))
            || class_getInstanceVariable(type(of: object), name) != nil
    }
}
