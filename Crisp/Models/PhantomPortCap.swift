import Foundation

/// How many active displays have something behind them, given what the ports say.
///
/// `physicalActiveDisplayCount`'s shape filter rejects an entry with no panel behind it,
/// but it cannot reject the third kind, from #112: after an undock while asleep,
/// WindowServer re-enumerates the absent externals at the full wake with their EDID
/// identities intact, so they are active, 16-bit and completely real-looking, and stay
/// that way until the dock goes back in. What actually left with the cable is the port's
/// transport node, so the count of externals is capped at the number of ports that can be
/// carrying one.
enum PhantomPortCap {
    /// - Parameters:
    ///   - builtin: active displays that are the built-in panel. Never capped: the panel
    ///     is not on a port, so what the ports say has nothing to do with it.
    ///   - external: active displays that arrived through a port.
    ///   - portCap: ports with a DisplayPort or Thunderbolt transport node and hot-plug
    ///     detect asserted, or nil when the machine exposes no transport nodes at all.
    ///     nil is "the signal is not available here", not "nothing is plugged in":
    ///     capping on it would black out a desk this rule has never seen. A machine that
    ///     does expose the nodes and reports none asserted is the #112 state, and 0 is
    ///     the right answer there.
    ///
    /// The cap is an upper bound. It never adds a display, so a dock with a spare socket
    /// reads the same as one without.
    static func activeCount(builtin: Int, external: Int, portCap: Int?) -> Int {
        guard let portCap else { return builtin + external }
        return builtin + min(external, portCap)
    }
}
