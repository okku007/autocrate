import Foundation

/// Trips on a failure (e.g. an iTunes 403/429 IP ban) and blocks all further attempts for a cooldown,
/// then half-opens to let one retry through. Shared across call sites so a single 403 stops the whole
/// app from hammering an already-blocked endpoint — which is what turns a brief rate-limit into a long
/// IP ban. Pairs with [RateLimiter]: the limiter paces healthy traffic, the breaker halts on failure.
public actor CircuitBreaker {
    private let cooldown: Duration
    private let clock = ContinuousClock()
    private var openUntil: ContinuousClock.Instant?

    public init(cooldown: Duration) { self.cooldown = cooldown }

    /// True while tripped and still within the cooldown. After the cooldown elapses it reports closed
    /// (half-open) so the next call may probe whether the endpoint has recovered.
    public var isOpen: Bool {
        guard let until = openUntil else { return false }
        return clock.now < until
    }

    /// Record a failure that should stop traffic (403/429/5xx, network error). Opens the breaker.
    public func recordFailure() { openUntil = clock.now.advanced(by: cooldown) }

    /// Record a success. Closes the breaker.
    public func recordSuccess() { openUntil = nil }
}
