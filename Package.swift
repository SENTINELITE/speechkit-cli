// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "speechkit-cli",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "speechkit",
            targets: ["speechkit"]
        ),
        .library(
            name: "SpeechKitCLICore",
            targets: ["SpeechKitCLICore"]
        ),
    ],
    dependencies: [
        .package(path: "../SpeechKit"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "SpeechKitCLICore",
            dependencies: [
                .product(name: "SpeechKit", package: "SpeechKit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "speechkit",
            dependencies: ["SpeechKitCLICore"]
        ),
        .testTarget(
            name: "SpeechKitCLICoreTests",
            dependencies: ["SpeechKitCLICore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
