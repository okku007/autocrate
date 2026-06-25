/// Whether reopening the panel should re-run the (expensive, rate-limited) query or keep showing
/// the results already on screen. Pure so it is unit-tested without AppKit; the engine projects its
/// `PanelState` and the live now-playing read down to two track ids before calling.
public enum RefreshDecision: Equatable, Sendable {
    case skip
    case refresh

    public static func evaluate(currentSeedID: String?, newSeedID: String?) -> RefreshDecision {
        if let currentSeedID, currentSeedID == newSeedID { return .skip }
        return .refresh
    }
}
