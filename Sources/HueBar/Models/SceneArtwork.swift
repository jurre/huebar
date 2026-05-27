import Foundation

struct SceneArtworkDescriptor: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case bundledImage(name: String)
        case paletteOnly
    }

    let source: Source

    var imageName: String? {
        guard case .bundledImage(let name) = source else { return nil }
        return name
    }

    init(scene: HueScene) {
        if let imageName = SceneArtworkCatalog.imageName(forPublicImage: scene.metadata.publicImage)
            ?? SceneArtworkCatalog.imageName(forSceneName: scene.name) {
            self.source = .bundledImage(name: imageName)
        } else {
            self.source = .paletteOnly
        }
    }
}

extension HueScene {
    var artwork: SceneArtworkDescriptor {
        SceneArtworkDescriptor(scene: self)
    }
}

extension HueSceneMetadata {
    var publicImage: ResourceLink? {
        guard image?.rtype == "public_image" else { return nil }
        return image
    }
}
