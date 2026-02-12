// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "HueBar",
    platforms: [
        .macOS(.v15),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", exact: "6.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "HueBar",
            path: "Sources/HueBar",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "HueBarTests",
            dependencies: [
                "HueBar",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
