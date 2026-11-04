import AppKit
import Observation
import SwiftUI
import Testing
@testable import HueBar

@Suite("Control accessibility", .serialized)
@MainActor
struct ControlAccessibilityTests {
    @Test func temperatureExposesValueAndCommitsAdjustments() throws {
        let mirek = Value(350)
        var changes: [Int] = []
        try withElements(
            ColorTemperatureSlider(mirek: Binding(get: { mirek.value }, set: { mirek.value = $0 })) {
                changes.append($0)
            }
        ) { elements in
            let slider = try #require(elements.first { $0.accessibilityLabel() == "Color temperature" })
            #expect(slider.accessibilityValueDescription() == "\(2857.formatted()) kelvin")
            #expect(changes.isEmpty)
            #expect(slider.accessibilityPerformIncrement())
            #expect(mirek.value > 350)
            #expect(changes == [mirek.value])
            #expect(slider.accessibilityValueDescription() == "\(Int(1_000_000.0 / Double(mirek.value)).formatted()) kelvin")
            #expect(slider.accessibilityPerformDecrement())
            #expect(mirek.value == 350)
            #expect(changes.count == 2)
        }
    }

    @Test(arguments: [0.0, 1.0])
    func wheelSaturationAdjustmentsStayWithinBounds(start: Double) throws {
        let xy = Value(CIEXYColor.fromHSB(hue: 0.3, saturation: start))
        try withElements(
            ColorWheelView(xy: Binding(get: { xy.value }, set: { xy.value = $0 })) { _ in }
        ) { elements in
            let saturation = try #require(elements.first { $0.accessibilityLabel() == "Color saturation" })
            if start == 1 {
                _ = saturation.accessibilityPerformIncrement()
            } else {
                _ = saturation.accessibilityPerformDecrement()
            }
            #expect(abs(xy.value.toHSB().saturation - start) < 0.01)
        }
    }

    @Test(arguments: [153, 500])
    func temperatureAdjustmentsStayWithinBounds(start: Int) throws {
        let mirek = Value(start)
        try withElements(
            ColorTemperatureSlider(mirek: Binding(get: { mirek.value }, set: { mirek.value = $0 })) { _ in }
        ) { elements in
            let slider = try #require(elements.first { $0.accessibilityLabel() == "Color temperature" })
            if start == 500 {
                _ = slider.accessibilityPerformIncrement()
            } else {
                _ = slider.accessibilityPerformDecrement()
            }
            #expect(mirek.value == start)
        }
    }

    @Test func wheelExposesIndependentHueAndSaturationAdjustments() throws {
        let xy = Value(CIEXYColor.fromHSB(hue: 0.3, saturation: 0.5))
        var changes: [CIEXYColor] = []
        try withElements(
            ColorWheelView(xy: Binding(get: { xy.value }, set: { xy.value = $0 })) { changes.append($0) }
        ) { elements in
            let hue = try #require(elements.first { $0.accessibilityLabel() == "Color hue" })
            let saturation = try #require(elements.first { $0.accessibilityLabel() == "Color saturation" })
            #expect(hue.accessibilityValueDescription() == "\(Int(xy.value.toHSB().hue * 360)) degrees")
            #expect(saturation.accessibilityValueDescription() == "\(Int(xy.value.toHSB().saturation * 100))%")
            #expect(changes.isEmpty)
            let original = xy.value.toHSB()
            #expect(hue.accessibilityPerformIncrement())
            #expect(xy.value.toHSB().hue > original.hue)
            #expect(abs(xy.value.toHSB().saturation - original.saturation) < 0.01)
            let afterHue = xy.value.toHSB()
            #expect(saturation.accessibilityPerformDecrement())
            #expect(xy.value.toHSB().saturation < afterHue.saturation)
            #expect(abs(xy.value.toHSB().hue - afterHue.hue) < 0.01)
            #expect(hue.accessibilityValueDescription() == "\(Int(xy.value.toHSB().hue * 360)) degrees")
            #expect(saturation.accessibilityValueDescription() == "\(Int(xy.value.toHSB().saturation * 100))%")
            #expect(changes.count == 2)
            #expect(changes.last?.x == xy.value.x)
            #expect(changes.last?.y == xy.value.y)
        }
    }

    @Observable
    final class Value<T> {
        var value: T

        init(_ value: T) {
            self.value = value
        }
    }

    @Test func hiddenToggleLabelsIdentifyTheirTargets() throws {
        let client = HueAPIClient(
            bridgeIP: "127.0.0.1", applicationKey: "fixture",
            session: URLSession(configuration: .ephemeral)
        )
        let light = HueLight(
            id: "light-1", owner: ResourceLink(rid: "device-1", rtype: "device"),
            metadata: LightMetadata(name: "Desk lamp", archetype: nil), on: OnState(on: false)
        )
        let room = Room(
            id: "room-1", metadata: GroupMetadata(name: "Living room", archetype: nil),
            services: [], children: []
        )
        withElements(LightCard(apiClient: client, light: light)) { elements in
            #expect(elements.contains { $0.accessibilityLabel() == "Toggle Desk lamp" })
        }
        withElements(RoomDetailView(apiClient: client, target: .room(room), onBack: {})) { elements in
            #expect(elements.contains { $0.accessibilityLabel() == "Toggle Living room" })
        }
        let zone = Zone(
            id: "zone-1", metadata: GroupMetadata(name: "Upstairs", archetype: nil),
            services: [], children: []
        )
        withElements(RoomDetailView(apiClient: client, target: .zone(zone), onBack: {})) { elements in
            #expect(elements.contains { $0.accessibilityLabel() == "Toggle Upstairs" })
        }
    }

    private func withElements<Content: View>(
        _ content: Content, check: ([Element]) throws -> Void
    ) rethrows {
        NSApplication.shared.accessibilitySetValue(
            true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
        )
        let host = NSHostingView(rootView: content.frame(width: 300, height: 300))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        try check((host.accessibilityChildren() as? [NSObject] ?? []).flatMap { descendants(of: $0) })
    }

    private func descendants(of element: NSObject) -> [Element] {
        let object: AnyObject = element
        let children = object.accessibilityChildren?() as? [NSObject] ?? []
        return [Element(object: element)] + children.flatMap {
            descendants(of: $0)
        }
    }

    // SwiftUI nodes implement accessibility selectors without declaring NSAccessibilityProtocol conformance.
    private struct Element {
        let object: AnyObject

        func accessibilityLabel() -> String? {
            object.accessibilityLabel?()
        }

        func accessibilityValueDescription() -> String? {
            object.accessibilityValueDescription?()
        }

        func accessibilityPerformIncrement() -> Bool {
            let result = object.accessibilityPerformIncrement?() ?? false
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            return result
        }

        func accessibilityPerformDecrement() -> Bool {
            let result = object.accessibilityPerformDecrement?() ?? false
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            return result
        }
    }
}
