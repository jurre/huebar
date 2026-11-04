import AppKit
import SwiftUI
import Testing
@testable import HueBar

@Suite("Detail card appearance", .serialized)
@MainActor
struct DetailCardAppearanceTests {
    @Test(arguments: [ColorScheme.light, .dark])
    func sceneHasVividTopAndShadedBottom(scheme: ColorScheme) throws {
        let scene = makeScene(name: "Sunset", hues: [0.02, 0.12], brightness: 5)
        let bitmap = try render(
            SceneCard(scene: scene, isActive: false, onTap: {}),
            width: 90, scheme: scheme
        )
        try expectVividShading(bitmap)
    }

    @Test(arguments: [ColorScheme.light, .dark], [1.0, 100.0])
    func lightHasVividTopAndShadedBottom(scheme: ColorScheme, brightness: Double) throws {
        let client = makeClient()
        let light = makeLight(name: "Lamp", hue: 0.08, brightness: brightness)
        let bitmap = try render(
            LightCard(apiClient: client, light: light),
            width: 140, scheme: scheme
        )
        try expectVividShading(bitmap)
    }

    @Test func scenePalettePreservesSourceHuesWithoutDimming() {
        let scene = makeScene(name: "Colors", hues: [0.02, 0.6, 0.8], brightness: 1)
        let expected = scene.paletteEntries.map { entry in
            switch entry {
            case .xy(let xy, _): return xy.displayColor().resolve(in: .init())
            case .colorTemperature(let mirek, _):
                return CIEXYColor.colorFromMirek(mirek).resolve(in: .init())
            }
        }
        #expect(scene.paletteColors.map { $0.resolve(in: .init()) } == expected)
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func daylightSceneUsesReadableDarkTitle(scheme: ColorScheme) throws {
        let bitmap = try render(
            SceneCard(scene: makeTemperatureScene(mirek: 153), isActive: false, onTap: {}),
            width: 90, scheme: scheme
        )
        let values = (bitmap.pixelsWide / 8..<bitmap.pixelsWide * 7 / 8).flatMap { x in
            (bitmap.pixelsHigh * 4 / 5..<bitmap.pixelsHigh * 9 / 10).compactMap { y in
                bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB).map {
                    max($0.redComponent, $0.greenComponent, $0.blueComponent)
                }
            }
        }
        #expect(try #require(values.min()) < 0.1)
    }

    @Test(arguments: [153, 370, 500])
    func temperatureSceneUsesUndimmedColor(mirek: Int) throws {
        let scene = makeTemperatureScene(mirek: mirek)
        let actual = try #require(scene.paletteColors.first).resolve(in: .init())
        #expect(actual == CIEXYColor.colorFromMirek(mirek).resolve(in: .init()))
    }

    @Test func emptyScenePaletteStaysEmpty() {
        #expect(makeScene(name: "Unknown", hues: [], brightness: 50).paletteColors.isEmpty)
    }

    @Test func lightCardSwatchPreservesBrightnessStateAndFallbacks() {
        var light = makeLight(name: "Lamp", hue: 0.65, brightness: 1)
        let dim = light.cardColor.resolve(in: .init())
        light.dimming = DimmingState(brightness: 100)
        #expect(light.cardColor.resolve(in: .init()) == dim)
        #expect(light.dimming?.brightness == 100)
        light.color = nil
        #expect(light.cardColor.resolve(in: .init()) == CIEXYColor.colorFromMirek(370).resolve(in: .init()))
        light.colorTemperature = LightColorTemperature(mirek: 153, mirekValid: true)
        #expect(light.cardColor.resolve(in: .init()) == CIEXYColor.colorFromMirek(153).resolve(in: .init()))
    }

    private func expectVividShading(_ bitmap: NSBitmapImageRep) throws {
        // Avoid text, icons and native controls while sampling the production fill.
        let top = try #require(
            bitmap.colorAt(x: bitmap.pixelsWide / 2, y: 6)?.usingColorSpace(.sRGB)
        )
        let bottom = try #require(
            bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh - 6)?.usingColorSpace(.sRGB)
        )
        let topValue = max(top.redComponent, top.greenComponent, top.blueComponent)
        let bottomValue = max(bottom.redComponent, bottom.greenComponent, bottom.blueComponent)
        #expect(topValue >= 0.85)
        #expect(topValue - bottomValue >= 0.25)
    }

    private func render(
        _ view: some View, width: CGFloat, scheme: ColorScheme
    ) throws -> NSBitmapImageRep {
        let host = NSHostingView(rootView:
            view.frame(width: width).environment(\.colorScheme, scheme)
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
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        host.layoutSubtreeIfNeeded()
        host.cacheDisplay(in: host.bounds, to: bitmap)
        return bitmap
    }

    private func makeClient() -> HueAPIClient {
        HueAPIClient(
            bridgeIP: "127.0.0.1", applicationKey: "fixture",
            session: URLSession(configuration: .ephemeral)
        )
    }

    private func makeLight(name: String, hue: Double, brightness: Double) -> HueLight {
        HueLight(
            id: name, owner: ResourceLink(rid: "device", rtype: "device"),
            metadata: LightMetadata(name: name, archetype: "classic_bulb"),
            on: OnState(on: true), dimming: DimmingState(brightness: brightness),
            color: LightColor(xy: .fromHSB(hue: hue, saturation: 0.8))
        )
    }

    private func makeScene(name: String, hues: [Double], brightness: Double) -> HueScene {
        HueScene(
            id: name, type: "scene", metadata: HueSceneMetadata(name: name, image: nil),
            group: ResourceLink(rid: "room", rtype: "room"),
            palette: HueScenePalette(
                color: hues.map {
                    HueScenePaletteColor(
                        color: HueColorValue(xy: .fromHSB(hue: $0, saturation: 0.8)),
                        dimming: HueScenePaletteDimming(brightness: brightness)
                    )
                },
                dimming: [], colorTemperature: []
            ), autoDynamic: nil
        )
    }

    private func makeTemperatureScene(mirek: Int) -> HueScene {
        HueScene(
            id: "temperature-\(mirek)", type: "scene",
            metadata: HueSceneMetadata(name: "Daylight", image: nil),
            group: ResourceLink(rid: "room", rtype: "room"),
            palette: HueScenePalette(
                color: [], dimming: [], colorTemperature: [
                    HueScenePaletteColorTemp(
                        colorTemperature: HueColorTemperature(mirek: mirek),
                        dimming: HueScenePaletteDimming(brightness: 5)
                    ),
                ]
            ), autoDynamic: nil
        )
    }
}
