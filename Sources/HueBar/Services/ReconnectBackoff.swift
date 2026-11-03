import Foundation

/// Exponential back-off for event stream reconnects.
///
/// The delay only resets after a connection stayed up for `healthyConnectionDuration`. A bridge that
/// accepts the connection and closes it right away keeps backing off instead of being reconnected
/// (and fully resynced) in a tight loop.
struct ReconnectBackoff: Sendable {
    static let initialDelay: Duration = .seconds(1)
    static let maximumDelay: Duration = .seconds(30)
    static let healthyConnectionDuration: Duration = .seconds(10)

    private var nextDelay = ReconnectBackoff.initialDelay

    /// How long to wait before the next attempt. `connectionDuration` is how long the connection
    /// that just ended stayed up (`.zero` if it never connected).
    mutating func delay(afterConnectionLasting connectionDuration: Duration) -> Duration {
        if connectionDuration >= Self.healthyConnectionDuration {
            nextDelay = Self.initialDelay
        }
        let delay = nextDelay
        nextDelay = min(nextDelay * 2, Self.maximumDelay)
        return delay
    }
}
