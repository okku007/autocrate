import Foundation

/// Pure helpers for the scanner's progress line: linear ETA + mm:ss formatting.
public enum ScanProgress {
    /// Linear extrapolation of remaining time. nil until at least one item is done.
    public static func etaSeconds(scanned: Int, total: Int, elapsed: TimeInterval) -> TimeInterval? {
        guard scanned > 0 else { return nil }
        let perItem = elapsed / Double(scanned)
        return perItem * Double(max(0, total - scanned))
    }

    /// "mm:ss", or "--:--" for nil.
    public static func format(_ seconds: TimeInterval?) -> String {
        guard let s = seconds, s.isFinite, s >= 0 else { return "--:--" }
        let total = Int(s.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
