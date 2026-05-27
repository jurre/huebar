import Foundation

struct OptimisticUpdateTracker: Sendable {
    enum ResourceKind: Sendable, Hashable {
        case groupedLight
        case light
    }

    enum Field: Sendable {
        case on
        case brightness
        case color
        case colorTemperature
    }

    enum Value: Sendable {
        case on(Bool)
        case brightness(Double)
        case color(CIEXYColor)
        case colorTemperature(Int)
    }

    static let protectionWindow: TimeInterval = 3.0

    private var updates: [ResourceKey: PendingLightUpdate] = [:]

    mutating func record(_ value: Value, for kind: ResourceKind, id: String, now: Date = Date()) {
        let key = ResourceKey(kind: kind, id: id)
        Self.record(value, in: &updates[key, default: PendingLightUpdate()], now: now)
    }

    mutating func clear(_ field: Field, for kind: ResourceKind, id: String) {
        let key = ResourceKey(kind: kind, id: id)
        guard var pending = updates[key] else { return }
        Self.clear(field, from: &pending)
        if pending.isEmpty {
            updates[key] = nil
        } else {
            updates[key] = pending
        }
    }

    mutating func filter(_ event: HueEventResource, kind: ResourceKind, now: Date = Date()) -> HueEventResource {
        let key = ResourceKey(kind: kind, id: event.id)
        return Self.filter(event, key: key, pendingUpdates: &updates, now: now)
    }

    private static func filter(
        _ event: HueEventResource,
        key: ResourceKey,
        pendingUpdates: inout [ResourceKey: PendingLightUpdate],
        now: Date
    ) -> HueEventResource {
        guard var pending = pendingUpdates[key] else { return event }

        var on = event.on
        var dimming = event.dimming
        var color = event.color
        var colorTemperature = event.colorTemperature

        Self.filter(&on, pending: &pending.on, now: now) { eventValue, pendingValue in
            eventValue.on == pendingValue
        }
        Self.filter(&dimming, pending: &pending.brightness, now: now) { eventValue, pendingValue in
            Self.brightnessMatches(eventValue.brightness, pendingValue)
        }
        Self.filter(&color, pending: &pending.color, now: now) { eventValue, pendingValue in
            Self.colorMatches(eventValue.xy, pendingValue)
        }
        Self.filter(&colorTemperature, pending: &pending.colorTemperature, now: now) { eventValue, pendingValue in
            eventValue.mirek == pendingValue
        }

        if pending.isEmpty {
            pendingUpdates[key] = nil
        } else {
            pendingUpdates[key] = pending
        }

        return HueEventResource(
            id: event.id,
            type: event.type,
            on: on,
            dimming: dimming,
            color: color,
            colorTemperature: colorTemperature,
            status: event.status,
            metadata: event.metadata,
            speed: event.speed
        )
    }

    private static func record(_ value: Value, in pending: inout PendingLightUpdate, now: Date) {
        switch value {
        case let .on(on):
            pending.on = Self.pending(on, now: now)
        case let .brightness(brightness):
            pending.brightness = Self.pending(brightness, now: now)
        case let .color(xy):
            pending.color = Self.pending(xy, now: now)
        case let .colorTemperature(mirek):
            pending.colorTemperature = Self.pending(mirek, now: now)
        }
    }

    private static func clear(_ field: Field, from pending: inout PendingLightUpdate) {
        switch field {
        case .on:
            pending.on = nil
        case .brightness:
            pending.brightness = nil
        case .color:
            pending.color = nil
        case .colorTemperature:
            pending.colorTemperature = nil
        }
    }

    private static func pending<Value: Sendable>(_ value: Value, now: Date) -> PendingValue<Value> {
        PendingValue(value: value, expiresAt: now.addingTimeInterval(Self.protectionWindow))
    }

    private static func filter<EventValue, Pending>(
        _ eventValue: inout EventValue?,
        pending pendingValue: inout PendingValue<Pending>?,
        now: Date,
        matches: (EventValue, Pending) -> Bool
    ) {
        guard let activePending = pendingValue else { return }
        guard !activePending.isExpired(at: now) else {
            pendingValue = nil
            return
        }
        guard let eventValueToCompare = eventValue else { return }
        if matches(eventValueToCompare, activePending.value) {
            pendingValue = nil
        } else {
            eventValue = nil
        }
    }

    private static func brightnessMatches(_ lhs: Double, _ rhs: Double) -> Bool {
        // Hue stores brightness in 254 internal levels, so values can round-trip
        // slightly off from the percentage we sent.
        abs(lhs - rhs) <= 0.5
    }

    private static func colorMatches(_ lhs: CIEXYColor, _ rhs: CIEXYColor) -> Bool {
        abs(lhs.x - rhs.x) <= 0.0001 && abs(lhs.y - rhs.y) <= 0.0001
    }
}

private struct ResourceKey: Hashable, Sendable {
    let kind: OptimisticUpdateTracker.ResourceKind
    let id: String
}

private struct PendingLightUpdate: Sendable {
    var on: PendingValue<Bool>?
    var brightness: PendingValue<Double>?
    var color: PendingValue<CIEXYColor>?
    var colorTemperature: PendingValue<Int>?

    var isEmpty: Bool {
        on == nil && brightness == nil && color == nil && colorTemperature == nil
    }
}

private struct PendingValue<Value: Sendable>: Sendable {
    let value: Value
    let expiresAt: Date

    func isExpired(at now: Date) -> Bool {
        now >= expiresAt
    }
}
