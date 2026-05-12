import Foundation
import Testing
@testable import HueBar

@Suite("OptimisticUpdateTracker")
struct OptimisticUpdateTrackerTests {
    private let now = Date(timeIntervalSince1970: 0)

    @Test("Stale grouped light brightness events do not overwrite a pending local change")
    func staleGroupedLightBrightnessIgnored() throws {
        // Arrange
        var tracker = OptimisticUpdateTracker()
        var groupedLights = [
            GroupedLight(id: "gl-1", on: OnState(on: true), dimming: DimmingState(brightness: 40.0), colorTemperature: nil),
        ]
        tracker.record(.brightness(40.0), for: .groupedLight, id: "gl-1", now: now)
        let staleEvent = HueEventResource(
            id: "gl-1",
            type: "grouped_light",
            on: nil,
            dimming: DimmingState(brightness: 12.0),
            color: nil,
            colorTemperature: nil,
            status: nil,
            metadata: nil,
            speed: nil
        )

        // Act
        let filteredEvent = tracker.filter(staleEvent, kind: .groupedLight, now: now)
        EventStreamUpdater.apply(filteredEvent, to: &groupedLights)

        // Assert
        #expect(groupedLights[0].brightness == 40.0)
    }

    @Test("Matching grouped light brightness event confirms the pending local change")
    func matchingGroupedLightBrightnessClearsPendingChange() throws {
        // Arrange
        var tracker = OptimisticUpdateTracker()
        var groupedLights = [
            GroupedLight(id: "gl-1", on: OnState(on: true), dimming: DimmingState(brightness: 40.0), colorTemperature: nil),
        ]
        tracker.record(.brightness(40.0), for: .groupedLight, id: "gl-1", now: now)
        let matchingEvent = HueEventResource(
            id: "gl-1",
            type: "grouped_light",
            on: nil,
            dimming: DimmingState(brightness: 40.0),
            color: nil,
            colorTemperature: nil,
            status: nil,
            metadata: nil,
            speed: nil
        )
        let laterEvent = HueEventResource(
            id: "gl-1",
            type: "grouped_light",
            on: nil,
            dimming: DimmingState(brightness: 65.0),
            color: nil,
            colorTemperature: nil,
            status: nil,
            metadata: nil,
            speed: nil
        )

        // Act
        EventStreamUpdater.apply(tracker.filter(matchingEvent, kind: .groupedLight, now: now), to: &groupedLights)
        EventStreamUpdater.apply(tracker.filter(laterEvent, kind: .groupedLight, now: now), to: &groupedLights)

        // Assert
        #expect(groupedLights[0].brightness == 65.0)
    }

    @Test("Approximate grouped light brightness match confirms the pending local change")
    func approximateGroupedLightBrightnessClearsPendingChange() throws {
        // Arrange
        var tracker = OptimisticUpdateTracker()
        var groupedLights = [
            GroupedLight(id: "gl-1", on: OnState(on: true), dimming: DimmingState(brightness: 40.0), colorTemperature: nil),
        ]
        tracker.record(.brightness(40.0), for: .groupedLight, id: "gl-1", now: now)
        let roundedEvent = HueEventResource(
            id: "gl-1",
            type: "grouped_light",
            on: nil,
            dimming: DimmingState(brightness: 40.39),
            color: nil,
            colorTemperature: nil,
            status: nil,
            metadata: nil,
            speed: nil
        )
        let laterEvent = HueEventResource(
            id: "gl-1",
            type: "grouped_light",
            on: nil,
            dimming: DimmingState(brightness: 65.0),
            color: nil,
            colorTemperature: nil,
            status: nil,
            metadata: nil,
            speed: nil
        )

        // Act
        EventStreamUpdater.apply(tracker.filter(roundedEvent, kind: .groupedLight, now: now), to: &groupedLights)
        EventStreamUpdater.apply(tracker.filter(laterEvent, kind: .groupedLight, now: now), to: &groupedLights)

        // Assert
        #expect(groupedLights[0].brightness == 65.0)
    }

    @Test("Older grouped light brightness confirmation does not overwrite a newer pending value")
    func olderGroupedLightBrightnessConfirmationIgnored() throws {
        // Arrange
        var tracker = OptimisticUpdateTracker()
        var groupedLights = [
            GroupedLight(id: "gl-1", on: OnState(on: true), dimming: DimmingState(brightness: 70.0), colorTemperature: nil),
        ]
        tracker.record(.brightness(50.0), for: .groupedLight, id: "gl-1", now: now)
        tracker.record(.brightness(70.0), for: .groupedLight, id: "gl-1", now: now)
        let olderEvent = HueEventResource(
            id: "gl-1",
            type: "grouped_light",
            on: nil,
            dimming: DimmingState(brightness: 50.0),
            color: nil,
            colorTemperature: nil,
            status: nil,
            metadata: nil,
            speed: nil
        )
        let newerEvent = HueEventResource(
            id: "gl-1",
            type: "grouped_light",
            on: nil,
            dimming: DimmingState(brightness: 70.0),
            color: nil,
            colorTemperature: nil,
            status: nil,
            metadata: nil,
            speed: nil
        )

        // Act
        EventStreamUpdater.apply(tracker.filter(olderEvent, kind: .groupedLight, now: now), to: &groupedLights)
        EventStreamUpdater.apply(tracker.filter(newerEvent, kind: .groupedLight, now: now), to: &groupedLights)

        // Assert
        #expect(groupedLights[0].brightness == 70.0)
    }

    @Test("Expired grouped light brightness protection allows bridge state to apply")
    func expiredGroupedLightBrightnessProtectionAllowsEvent() throws {
        // Arrange
        var tracker = OptimisticUpdateTracker()
        var groupedLights = [
            GroupedLight(id: "gl-1", on: OnState(on: true), dimming: DimmingState(brightness: 40.0), colorTemperature: nil),
        ]
        tracker.record(.brightness(40.0), for: .groupedLight, id: "gl-1", now: now)
        let staleEvent = HueEventResource(
            id: "gl-1",
            type: "grouped_light",
            on: nil,
            dimming: DimmingState(brightness: 12.0),
            color: nil,
            colorTemperature: nil,
            status: nil,
            metadata: nil,
            speed: nil
        )

        // Act
        let filteredEvent = tracker.filter(
            staleEvent,
            kind: .groupedLight,
            now: now.addingTimeInterval(OptimisticUpdateTracker.protectionWindow + 0.1)
        )
        EventStreamUpdater.apply(filteredEvent, to: &groupedLights)

        // Assert
        #expect(groupedLights[0].brightness == 12.0)
    }

    @Test("Stale light toggle events do not overwrite a pending local change")
    func staleLightToggleIgnored() throws {
        // Arrange
        var tracker = OptimisticUpdateTracker()
        var lights = [
            HueLight(
                id: "light-1",
                owner: ResourceLink(rid: "device-1", rtype: "device"),
                metadata: LightMetadata(name: "Desk Lamp", archetype: "table_wash"),
                on: OnState(on: false),
                dimming: DimmingState(brightness: 50.0),
                color: nil,
                colorTemperature: nil
            ),
        ]
        tracker.record(.on(false), for: .light, id: "light-1", now: now)
        let staleEvent = HueEventResource(
            id: "light-1",
            type: "light",
            on: OnState(on: true),
            dimming: nil,
            color: nil,
            colorTemperature: nil,
            status: nil,
            metadata: nil,
            speed: nil
        )

        // Act
        let filteredEvent = tracker.filter(staleEvent, kind: .light, now: now)
        EventStreamUpdater.apply(filteredEvent, to: &lights)

        // Assert
        #expect(lights[0].isOn == false)
    }
}
