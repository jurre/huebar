import Foundation
import Testing
@testable import HueBar

@Suite("SceneArtwork")
struct SceneArtworkTests {
    @Test("Known CDP public image ids map to bundled artwork even when the scene name differs")
    func knownCDPPublicImageIDMapsToBundledArtwork() throws {
        // Arrange
        let scene = try createScene(
            id: "scene-custom-race",
            name: "Race",
            image: ResourceLink(rid: "03afc233-4845-4fe8-b2f4-f79873666326", rtype: "public_image")
        )

        // Act
        let artwork = SceneArtworkDescriptor(scene: scene)

        // Assert
        #expect(artwork.source == .bundledImage(name: "bahrain"))
        #expect(artwork.imageName == "bahrain")
    }

    @Test("Recipe public image ids map to bundled artwork")
    func recipePublicImageIDMapsToBundledArtwork() throws {
        // Arrange
        let scene = try createScene(
            id: "scene-custom-focus",
            name: "Focus",
            image: ResourceLink(rid: "7fd2ccc5-5749-4142-b7a5-66405a676f03", rtype: "public_image")
        )

        // Act
        let artwork = SceneArtworkDescriptor(scene: scene)

        // Assert
        #expect(artwork.source == .bundledImage(name: "energize"))
        #expect(artwork.imageName == "energize")
    }

    @Test("Scene names fall back to bundled artwork when no known public image id exists")
    func sceneNameFallsBackToBundledArtwork() throws {
        // Arrange
        let scene = try createScene(
            id: "scene-vapor-wave",
            name: "Vapor wave",
            image: nil
        )

        // Act
        let artwork = SceneArtworkDescriptor(scene: scene)

        // Assert
        #expect(artwork.source == .bundledImage(name: "vapor_wave"))
        #expect(artwork.imageName == "vapor_wave")
    }

    @Test("Newer scene names fall back to bundled artwork when no known public image id exists")
    func newerSceneNameFallsBackToBundledArtwork() throws {
        // Arrange
        let scene = try createScene(
            id: "scene-woodland-toadstool",
            name: "Woodland toadstool",
            image: nil
        )

        // Act
        let artwork = SceneArtworkDescriptor(scene: scene)

        // Assert
        #expect(artwork.source == .bundledImage(name: "woodland_toadstool"))
        #expect(artwork.imageName == "woodland_toadstool")
    }

    @Test("Unknown scenes fall back to palette-only artwork")
    func unknownScenesFallBackToPaletteOnlyArtwork() throws {
        // Arrange
        let scene = try createScene(
            id: "scene-family-dinner",
            name: "Family dinner",
            image: ResourceLink(rid: "unknown-public-image", rtype: "public_image")
        )

        // Act
        let artwork = SceneArtworkDescriptor(scene: scene)

        // Assert
        #expect(artwork.source == .paletteOnly)
        #expect(artwork.imageName == nil)
    }

    @Test("Non-public image references do not drive artwork selection")
    func nonPublicImageReferenceDoesNotDriveArtworkSelection() throws {
        // Arrange
        let scene = try createScene(
            id: "scene-mystery",
            name: "Mystery",
            image: ResourceLink(rid: "7fd2ccc5-5749-4142-b7a5-66405a676f03", rtype: "device")
        )

        // Act
        let artwork = SceneArtworkDescriptor(scene: scene)

        // Assert
        #expect(artwork.source == .paletteOnly)
        #expect(artwork.imageName == nil)
    }

    @Test("Every catalog entry has a bundled image asset")
    func everyCatalogEntryHasBundledImageAsset() {
        // Arrange
        let imageNames = SceneArtworkCatalog.allImageNames

        // Act
        let missing = imageNames.filter { SceneArtworkCatalog.url(forImageNamed: $0) == nil }

        // Assert
        #expect(missing.isEmpty)
    }

    private func createScene(id: String, name: String, image: ResourceLink?) throws -> HueScene {
        let imageJSON: String
        if let image {
            imageJSON = #","image":{"rid":"\#(image.rid)","rtype":"\#(image.rtype)"}"#
        } else {
            imageJSON = ""
        }

        let json = """
        {
            "id": "\(id)",
            "metadata": {"name": "\(name)"\(imageJSON)},
            "group": {"rid": "room-1", "rtype": "room"},
            "palette": {
                "color": [
                    {"color": {"xy": {"x": 0.5, "y": 0.4}}, "dimming": {"brightness": 80.0}},
                    {"color": {"xy": {"x": 0.3, "y": 0.6}}, "dimming": {"brightness": 50.0}}
                ],
                "dimming": []
            }
        }
        """

        return try JSONDecoder().decode(HueScene.self, from: Data(json.utf8))
    }
}
