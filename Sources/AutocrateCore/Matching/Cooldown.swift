import Foundation

/// A pure, synchronous minimum-interval gate for a user-triggered action (the manual refresh
/// button). Unlike `RateLimiter` (an actor that queues/suspends callers), this answers a yes/no
/// "is it allowed right now" so the UI can bind a disabled state and silently drop early taps.
public struct Cooldown: Equatable, Sendable {
    public let interval: TimeInterval
    public init(interval: TimeInterval) { self.interval = interval }

    /// True if `interval` seconds have elapsed since `last` (or there was no prior action).
    public func allows(now: Date, last: Date?) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= interval
    }

    /// Seconds until the next action is allowed; 0 if allowed now. Reserved for a future
    /// live countdown hint (e.g. a "Refresh available in 42s" tooltip) — not yet wired to UI.
    public func remaining(now: Date, last: Date?) -> TimeInterval {
        guard let last else { return 0 }
        return max(0, interval - now.timeIntervalSince(last))
    }
}
