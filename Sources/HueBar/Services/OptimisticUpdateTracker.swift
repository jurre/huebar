import Foundation

struct OptimisticUpdateTracker: Sendable {
    enum ResourceKind: Sendable {
        case groupedLight
        case light
    }

    static let protectionWindow: TimeInterval = 3.0

    private var groupedLights: [String: PendingLightUpdate] = [:]
    private var lights: [String: PendingLightUpdate] = [:]

    mutating func recordGroupedLightOn(id: String, on: Bool, now: Date = Date()) {
        groupedLights[id, default: PendingLightUpdate()].on = Self.pending(on, now: now)
    }

    mutating func recordGroupedLightBrightness(id: String, brightness: Double, now: Date = Date()) {
        groupedLights[id, default: PendingLightUpdate()].brightness = Self.pending(brightness, now: now)
    }

    mutating func recordGroupedLightColorTemperature(id: String, mirek: Int, now: Date = Date()) {
        groupedLights[id, default: PendingLightUpdate()].colorTemperature = Self.pending(mirek, now: now)
    }

    mutating func recordLightOn(id: String, on: Bool, now: Date = Date()) {
        lights[id, default: PendingLightUpdate()].on = Self.pending(on, now: now)
    }

    mutating func recordLightBrightness(id: String, brightness: Double, now: Date = Date()) {
        lights[id, default: PendingLightUpdate()].brightness = Self.pending(brightness, now: now)
    }

    mutating func recordLightColor(id: String, xy: CIEXYColor, now: Date = Date()) {
        lights[id, default: PendingLightUpdate()].color = Self.pending(xy, now: now)
    }

    mutating func recordLightColorTemperature(id: String, mirek: Int, now: Date = Date()) {
        lights[id, default: PendingLightUpdate()].colorTemperature = Self.pending(mirek, now: now)
    }

    mutating func clearGroupedLightOn(id: String) {
        Self.clear(id: id, in: &groupedLights) { $0.on = nil }
    }

    mutating func clearGroupedLightBrightness(id: String) {
        Self.clear(id: id, in: &groupedLights) { $0.brightness = nil }
    }

    mutating func clearGroupedLightColorTemperature(id: String) {
        Self.clear(id: id, in: &groupedLights) { $0.colorTemperature = nil }
    }

    mutating func clearLightOn(id: String) {
        Self.clear(id: id, in: &lights) { $0.on = nil }
    }

    mutating func clearLightBrightness(id: String) {
        Self.clear(id: id, in: &lights) { $0.brightness = nil }
    }

    mutating func clearLightColor(id: String) {
        Self.clear(id: id, in: &lights) { $0.color = nil }
    }

    mutating func clearLightColorTemperature(id: String) {
        Self.clear(id: id, in: &lights) { $0.colorTemperature = nil }
    }

    mutating func filter(_ event: HueEventResource, kind: ResourceKind, now: Date = Date()) -> HueEventResource {
        switch kind {
        case .groupedLight:
            return Self.filter(event, pendingUpdates: &groupedLights, now: now)
        case .light:
            return Self.filter(event, pendingUpdates: &lights, now: now)
        }
    }

    private static func pending<Value: Sendable>(_ value: Value, now: Date) -> PendingValue<Value> {
        PendingValue(value: value, expiresAt: now.addingTimeInterval(Self.protectionWindow))
    }

    private static func filter(
        _ event: HueEventResource,
        pendingUpdates: inout [String: PendingLightUpdate],
        now: Date
    ) -> HueEventResource {
        guard var pending = pendingUpdates[event.id] else { return event }

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
            pendingUpdates[event.id] = nil
        } else {
            pendingUpdates[event.id] = pending
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

    private static func clear(
        id: String,
        in pendingUpdates: inout [String: PendingLightUpdate],
        clearField: (inout PendingLightUpdate) -> Void
    ) {
        guard var pending = pendingUpdates[id] else { return }
        clearField(&pending)
        if pending.isEmpty {
            pendingUpdates[id] = nil
        } else {
            pendingUpdates[id] = pending
        }
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
        abs(lhs - rhs) <= 0.5
    }

    private static func colorMatches(_ lhs: CIEXYColor, _ rhs: CIEXYColor) -> Bool {
        abs(lhs.x - rhs.x) <= 0.0001 && abs(lhs.y - rhs.y) <= 0.0001
    }
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
