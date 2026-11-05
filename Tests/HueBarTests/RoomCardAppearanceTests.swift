import AppKit
import SwiftUI
import Testing
@testable import HueBar

@Suite("Room card appearance", .serialized)
@MainActor
struct RoomCardAppearanceTests {
    @Test func roomPalettePreservesVividSourceColorsRegardlessOfBrightness() throws {
        let client = makeClient()
        let xy = CIEXYColor.fromHSB(hue: 0.08, saturation: 0.8)
        client.lights = [makeLight(id: "light-1", xy: xy, brightness: 5)]
        let dim = try #require(client.previewColors(for: "room-1").first).resolve(in: .init())
        client.lights[0].dimming = DimmingState(brightness: 100)
        let bright = try #require(client.previewColors(for: "room-1").first).resolve(in: .init())
        let source = xy.displayColor().resolve(in: .init())

        #expect(abs(dim.red - source.red) < 0.001)
        #expect(abs(dim.green - source.green) < 0.001)
        #expect(abs(dim.blue - source.blue) < 0.001)
        #expect(dim == bright)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func roomCardHasVividTopAndShadedBottom(scheme: ColorScheme) throws {
        let client = makeClient()
        client.lights = [
            makeLight(id: "light-1", xy: .fromHSB(hue: 0.08, saturation: 0.8), brightness: 40),
        ]
        let bitmap = try render(client: client, scheme: scheme)
        let x = bitmap.pixelsWide / 2
        let top = try #require(bitmap.colorAt(x: x, y: 8)?.usingColorSpace(.sRGB))
        let bottom = try #require(bitmap.colorAt(x: x, y: bitmap.pixelsHigh - 8)?.usingColorSpace(.sRGB))
        let topValue = max(top.redComponent, top.greenComponent, top.blueComponent)
        let bottomValue = max(bottom.redComponent, bottom.greenComponent, bottom.blueComponent)
        #expect(topValue >= 0.85)
        #expect(topValue - bottomValue >= 0.25)
    }

    @Test func roomAndZonePalettesKeepAllOnLightColors() {
        let client = makeClient()
        client.lights = [
            makeLight(id: "red", xy: .fromHSB(hue: 0, saturation: 0.9), brightness: 20),
            makeLight(id: "blue", xy: .fromHSB(hue: 0.66, saturation: 0.9), brightness: 80),
            makeLight(id: "off", xy: .fromHSB(hue: 0.33, saturation: 1), brightness: 100),
        ]
        client.lights[2].on = OnState(on: false)
        client.zones = [
            Zone(
                id: "zone-1", metadata: GroupMetadata(name: "Zone", archetype: nil),
                services: [], children: client.lights.map { ResourceLink(rid: $0.id, rtype: "light") }
            ),
        ]
        let expected = client.lights.prefix(2).compactMap { $0.color?.xy.displayColor().resolve(in: .init()) }
        #expect(client.previewColors(for: "room-1").map { $0.resolve(in: .init()) } == expected)
        #expect(client.previewColors(for: "zone-1").map { $0.resolve(in: .init()) } == expected)
        #expect(client.previewColors(for: nil).isEmpty)
        #expect(client.previewColors(for: "missing").isEmpty)
    }

    @Test(arguments: [153, 370, 500])
    func roomTemperaturePaletteDoesNotDimWithBulbs(mirek: Int) throws {
        let client = makeClient()
        client.lights = [makeLight(id: "white", xy: .fromHSB(hue: 0, saturation: 0), brightness: 1)]
        client.lights[0].color = nil
        client.lights[0].colorTemperature = LightColorTemperature(mirek: mirek, mirekValid: true)
        let color = try #require(client.previewColors(for: "room-1").first).resolve(in: .init())
        let expected = CIEXYColor.colorFromMirek(mirek).resolve(in: .init())
        #expect(color == expected)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func daylightCardKeepsLabelsReadable(scheme: ColorScheme) throws {
        let client = makeClient()
        client.lights = [makeLight(id: "white", xy: .fromHSB(hue: 0, saturation: 0), brightness: 40)]
        client.lights[0].color = nil
        client.lights[0].colorTemperature = LightColorTemperature(mirek: 153, mirekValid: true)
        let bitmap = try render(client: client, scheme: scheme)
        let background = try #require(
            bitmap.colorAt(x: bitmap.pixelsWide / 2, y: Int(Double(bitmap.pixelsHigh) * 0.36))?
                .usingColorSpace(.sRGB)
        )
        func linearize(_ component: CGFloat) -> Double {
            let value = Double(component)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = 0.2126 * linearize(background.redComponent)
            + 0.7152 * linearize(background.greenComponent)
            + 0.0722 * linearize(background.blueComponent)
        // Look for actual dark glyph pixels, not just a foreground-style decision.
        let scale = Double(bitmap.pixelsWide) / 300
        let labelPixels = (Int(66 * scale)..<Int(140 * scale)).flatMap { x in
            (Int(19 * scale)..<Int(32 * scale)).compactMap { y in
                bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
            }
        }
        let darkest = try #require(labelPixels.map {
            max($0.redComponent, $0.greenComponent, $0.blueComponent)
        }.min())
        #expect(darkest < 0.1)
        let contrast = (luminance + 0.05) / 0.05
        #expect(contrast >= 4.5)
    }

    enum SliderCardPalette: CaseIterable {
        case vivid
        case daylight
    }

    @Test(arguments: [ColorScheme.light, .dark], SliderCardPalette.allCases)
    func brightnessSliderHighlightsTheFilledSide(scheme: ColorScheme, palette: SliderCardPalette) throws {
        let client = makeClient()
        client.lights = [makeLight(id: "light-1", xy: .fromHSB(hue: 0.08, saturation: 0.8), brightness: 40)]
        if palette == .daylight {
            client.lights[0].color = nil
            client.lights[0].colorTemperature = LightColorTemperature(mirek: 153, mirekValid: true)
        }
        let bitmap = try render(client: client, scheme: scheme)
        let scale = Double(bitmap.pixelsWide) / 300
        func luma(x: Double, y: Double) throws -> Double {
            let color = try #require(bitmap.colorAt(x: Int(x * scale), y: Int(y * scale))?.usingColorSpace(.sRGB))
            return 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
        }
        // Card ends 1pt above the bitmap edge; the slider row sits above 14pt of padding.
        let height = Double(bitmap.pixelsHigh) / scale
        let rowBottom = height - 1 - 14
        let rowBand = stride(from: rowBottom - 20, through: rowBottom, by: 0.5)
        func strongestContrast(atX x: Double) throws -> Double {
            let background = try luma(x: x, y: rowBottom + 4)
            return try rowBand.map { abs(try luma(x: x, y: $0) - background) }.max() ?? 0
        }
        // Brightness 40% puts the thumb near x≈130; sample well clear of it and the sun icons.
        let filled = try strongestContrast(atX: 75)
        let remaining = try strongestContrast(atX: 225)
        #expect(filled >= 0.3, "filled side should stand out from the card (contrast \(filled))")
        #expect(filled >= remaining * 2, "filled side (\(filled)) should read as active vs remaining track (\(remaining))")
    }

    private func render(
        client: HueAPIClient, scheme: ColorScheme
    ) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView:
            LightRowView(
                apiClient: client, name: "Living room", archetype: "living_room",
                groupedLightId: "group-1", groupId: "room-1", onTap: {}
            )
            .padding(.vertical, 1)
            .frame(width: 300)
            .environment(\.colorScheme, scheme)
        )
        host.frame.size = host.fittingSize
        let window = NSWindow(
            contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
        window.contentView = host
        defer { window.close() }
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        // Glass-backed content needs a display pass before onAppear state settles.
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    private func makeClient() -> HueAPIClient {
        let client = HueAPIClient(
            bridgeIP: "127.0.0.1", applicationKey: "fixture",
            session: URLSession(configuration: .ephemeral)
        )
        client.rooms = [
            Room(
                id: "room-1", metadata: GroupMetadata(name: "Living room", archetype: "living_room"),
                services: [], children: [ResourceLink(rid: "device-1", rtype: "device")]
            ),
        ]
        client.groupedLights = [
            GroupedLight(id: "group-1", on: OnState(on: true), dimming: DimmingState(brightness: 40)),
        ]
        return client
    }

    private func makeLight(id: String, xy: CIEXYColor, brightness: Double) -> HueLight {
        HueLight(
            id: id, owner: ResourceLink(rid: "device-1", rtype: "device"),
            metadata: LightMetadata(name: id, archetype: nil), on: OnState(on: true),
            dimming: DimmingState(brightness: brightness), color: LightColor(xy: xy)
        )
    }
}
