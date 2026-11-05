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
            },
            expecting: ["Color temperature"]
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
            ColorWheelView(xy: Binding(get: { xy.value }, set: { xy.value = $0 })) { _ in },
            expecting: ["Color saturation"]
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
            ColorTemperatureSlider(mirek: Binding(get: { mirek.value }, set: { mirek.value = $0 })) { _ in },
            expecting: ["Color temperature"]
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
            ColorWheelView(xy: Binding(get: { xy.value }, set: { xy.value = $0 })) { changes.append($0) },
            expecting: ["Color hue", "Color saturation"]
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

    @Test func brightnessExposesValueAndWrapsAdjustmentsInAnEdit() throws {
        let brightness = Value(40.0)
        var edits: [Bool] = []
        try withElements(
            BrightnessSlider(
                value: Binding(get: { brightness.value }, set: { brightness.value = $0 }), color: .white
            ) { edits.append($0) }
                .accessibilityLabel("Office brightness")
                .accessibilityValue("\(Int(brightness.value))%"),
            expecting: ["Office brightness"]
        ) { elements in
            let slider = try #require(elements.first { $0.accessibilityLabel() == "Office brightness" })
            #expect(slider.accessibilityValueDescription() == "40%")
            #expect(edits.isEmpty)
            #expect(slider.accessibilityPerformIncrement())
            #expect(brightness.value > 40)
            // Card sliders commit on the end of an edit, so VoiceOver changes must close one.
            #expect(edits == [true, false])
            #expect(slider.accessibilityPerformDecrement())
            #expect(brightness.value == 40)
            #expect(edits == [true, false, true, false])
        }
    }

    @Test(arguments: [1.0, 100.0])
    func brightnessAdjustmentsStayWithinBounds(start: Double) throws {
        let brightness = Value(start)
        try withElements(
            BrightnessSlider(
                value: Binding(get: { brightness.value }, set: { brightness.value = $0 }), color: .white
            ) { _ in }
                .accessibilityLabel("Brightness"),
            expecting: ["Brightness"]
        ) { elements in
            let slider = try #require(elements.first { $0.accessibilityLabel() == "Brightness" })
            if start == 100 {
                _ = slider.accessibilityPerformIncrement()
            } else {
                _ = slider.accessibilityPerformDecrement()
            }
            #expect(brightness.value == start)
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
        try withElements(
            LightCard(apiClient: client, light: light), expecting: ["Toggle Desk lamp"]
        ) { elements in
            #expect(elements.contains { $0.accessibilityLabel() == "Toggle Desk lamp" })
        }
        try withElements(
            RoomDetailView(apiClient: client, target: .room(room), onBack: {}),
            expecting: ["Toggle Living room"]
        ) { elements in
            #expect(elements.contains { $0.accessibilityLabel() == "Toggle Living room" })
        }
        let zone = Zone(
            id: "zone-1", metadata: GroupMetadata(name: "Upstairs", archetype: nil),
            services: [], children: []
        )
        try withElements(
            RoomDetailView(apiClient: client, target: .zone(zone), onBack: {}),
            expecting: ["Toggle Upstairs"]
        ) { elements in
            #expect(elements.contains { $0.accessibilityLabel() == "Toggle Upstairs" })
        }
    }

    private func withElements<Content: View>(
        _ content: Content, expecting labels: [String], check: ([Element]) throws -> Void
    ) throws {
        let enhancedUI = NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface")
        NSApplication.shared.accessibilitySetValue(
            true, forAttribute: enhancedUI
        )
        try #require(
            (NSApplication.shared.accessibilityAttributeValue(enhancedUI) as? NSNumber)?.boolValue == true,
            "AXEnhancedUserInterface could not be enabled for hosted SwiftUI accessibility tests"
        )
        let host = NSHostingView(rootView: content.frame(width: 300, height: 300))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 300),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.close() }
        let deadline = Date().addingTimeInterval(5)
        repeat {
            host.layoutSubtreeIfNeeded()
            let elements = (host.accessibilityChildren() as? [NSObject] ?? []).flatMap { descendants(of: $0) }
            if labels.allSatisfy({ label in elements.contains { $0.accessibilityLabel() == label } }) {
                try check(elements)
                return
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        } while Date() < deadline
        Issue.record("Accessibility tree did not expose expected labels within 5 seconds: \(labels)")
    }

    private func descendants(of element: NSObject) -> [Element] {
        let object: AnyObject = element
        guard object.responds(to: #selector(NSAccessibilityProtocol.accessibilityChildren)) else {
            Issue.record("Accessibility element \(element) is missing required selector accessibilityChildren")
            return [Element(object: element)]
        }
        let children = object.accessibilityChildren?() as? [NSObject] ?? []
        return [Element(object: element)] + children.flatMap {
            descendants(of: $0)
        }
    }

    // SwiftUI nodes implement accessibility selectors without declaring NSAccessibilityProtocol conformance.
    private struct Element {
        let object: AnyObject

        func accessibilityLabel() -> String? {
            guard supports(#selector(NSAccessibilityProtocol.accessibilityLabel)) else { return nil }
            return object.accessibilityLabel?()
        }

        func accessibilityValueDescription() -> String? {
            guard supports(#selector(NSAccessibilityProtocol.accessibilityValueDescription)) else { return nil }
            return object.accessibilityValueDescription?()
        }

        func accessibilityPerformIncrement() -> Bool {
            guard supports(#selector(NSAccessibilityProtocol.accessibilityPerformIncrement)) else { return false }
            let result = object.accessibilityPerformIncrement?() ?? false
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            return result
        }

        func accessibilityPerformDecrement() -> Bool {
            guard supports(#selector(NSAccessibilityProtocol.accessibilityPerformDecrement)) else { return false }
            let result = object.accessibilityPerformDecrement?() ?? false
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            return result
        }

        private func supports(_ selector: Selector) -> Bool {
            guard object.responds(to: selector) else {
                Issue.record("Accessibility element \(object) is missing required selector \(NSStringFromSelector(selector))")
                return false
            }
            return true
        }
    }
}
