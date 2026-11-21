// swift-tools-version: 6.2

import Foundation
import PackageDescription

// The public build resolves versioned packages. Developers working across the
// three repositories can use sibling checkouts with this environment variable.
let useLocalPackages = ProcessInfo.processInfo.environment["SPEECHKIT_VOZ_USE_LOCAL_SPEECHKIT"] != nil
let speechKit: Package.Dependency = useLocalPackages
    ? .package(path: "../SpeechKit")
    : .package(url: "https://github.com/SENTINELITE/SpeechKit.git", from: "3.0.1")
let speechKitVoz: Package.Dependency = useLocalPackages
    ? .package(path: "../SpeechKit-Voz")
    : .package(url: "https://github.com/SENTINELITE/SpeechKit-Voz.git", from: "1.1.0")

let package = Package(
    name: "speechkit-cli",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(
            name: "speechkit",
            targets: ["SpeechKitExecutable"]
        ),
        .library(
            name: "SpeechKitCLICore",
            targets: ["SpeechKitCLICore"]
        ),
    ],
    dependencies: [
        speechKit,
        speechKitVoz,
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "SpeechKitCLICore",
            dependencies: [
                .product(name: "SpeechKit", package: "SpeechKit"),
                .product(name: "SpeechKitVoz", package: "SpeechKit-Voz"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "SpeechKitExecutable",
            dependencies: ["SpeechKitCLICore"],
            path: "Sources/speechkit"
        ),
        .testTarget(
            name: "SpeechKitCLICoreTests",
            dependencies: ["SpeechKitCLICore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
