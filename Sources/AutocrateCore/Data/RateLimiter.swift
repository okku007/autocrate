import Foundation

/// Enforces a minimum interval between operations so callers stay under a rate-limited API's
/// budget. Shared across every call site (interactive lookup, background pre-warm, discover) so they
/// draw from one budget rather than each blowing past the limit independently.
///
/// `acquire()` reserves the next slot synchronously (before any suspension), so concurrent callers
/// are queued and spaced `minInterval` apart instead of all firing at once.
public actor RateLimiter {
    private let minInterval: Duration
    private let clock = ContinuousClock()
    private var nextAllowed: ContinuousClock.Instant?

    public init(minInterval: Duration) { self.minInterval = minInterval }

    /// Suspends until the caller's reserved slot, then returns. Reserves the following slot for the
    /// next caller before suspending, so ordering is deterministic under concurrency.
    public func acquire() async {
        let now = clock.now
        let slot = max(nextAllowed ?? now, now)
        nextAllowed = slot.advanced(by: minInterval)
        if slot > now { try? await clock.sleep(until: slot, tolerance: nil) }
    }
}
