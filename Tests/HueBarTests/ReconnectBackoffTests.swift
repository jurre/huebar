import Testing
@testable import HueBar

struct ReconnectBackoffTests {

    @Test func delayDoublesFromInitialUpToMaximum() {
        var backoff = ReconnectBackoff()

        let delays = (0..<8).map { _ in backoff.delay(afterConnectionLasting: .zero) }

        #expect(delays == [
            .seconds(1), .seconds(2), .seconds(4), .seconds(8), .seconds(16),
            .seconds(30), .seconds(30), .seconds(30),
        ])
    }

    @Test func connectionClosedRightAfterConnectingKeepsBackingOff() {
        var backoff = ReconnectBackoff()
        _ = backoff.delay(afterConnectionLasting: .zero)

        #expect(backoff.delay(afterConnectionLasting: .milliseconds(50)) == .seconds(2))
        #expect(backoff.delay(afterConnectionLasting: .seconds(1)) == .seconds(4))
    }

    @Test func healthyConnectionResetsDelay() {
        var backoff = ReconnectBackoff()
        for _ in 0..<4 { _ = backoff.delay(afterConnectionLasting: .zero) }

        #expect(backoff.delay(afterConnectionLasting: ReconnectBackoff.healthyConnectionDuration) == .seconds(1))
        #expect(backoff.delay(afterConnectionLasting: .zero) == .seconds(2))
    }

    @Test func connectionJustUnderHealthyDurationDoesNotReset() {
        var backoff = ReconnectBackoff()
        for _ in 0..<3 { _ = backoff.delay(afterConnectionLasting: .zero) }

        let almostHealthy = ReconnectBackoff.healthyConnectionDuration - .milliseconds(1)

        #expect(backoff.delay(afterConnectionLasting: almostHealthy) == .seconds(8))
    }
}
