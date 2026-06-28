import AppKit

/// Detects whether the Autocrate app is running, so the scanner can refuse to write the shared
/// SQLite cache while the app holds it open (writing it then corrupts the open connection).
public enum AppRunningGuard {
    public static let bundleID = "dev.moksh.autocrate"
    public static func isAppRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }
}
