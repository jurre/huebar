// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HueBar",
    platforms: [
        .macOS(.v15),
    ],
    targets: [
        .executableTarget(
            name: "HueBar",
            path: "Sources/HueBar",
            exclude: ["Info.plist"]
        ),
    ]
)
