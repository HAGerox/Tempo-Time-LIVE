// swift-tools-version: 6.0
import PackageDescription

var products: [Product] = [
    .library(name: "TempoCore", targets: ["TempoCore"]),
    .executable(name: "tempo-analyze", targets: ["TempoAnalyze"])
]
var targets: [Target] = [
    .target(name: "TempoCore"),
    .target(name: "AudioBridge", publicHeadersPath: "include", linkerSettings: [
        .linkedFramework("CoreAudio", .when(platforms: [.macOS])),
        .linkedFramework("AudioToolbox", .when(platforms: [.macOS]))
    ]),
    .target(name: "TempoInput", dependencies: ["TempoCore", "AudioBridge"]),
    .executableTarget(name: "TempoAnalyze", dependencies: ["TempoCore"]),
    .testTarget(name: "TempoCoreTests", dependencies: ["TempoCore"]),
    .testTarget(name: "AudioBridgeTests", dependencies: ["AudioBridge"]),
    .testTarget(name: "TempoInputTests", dependencies: ["TempoInput", "TempoCore"])
]
#if os(macOS)
products.append(.executable(name: "tempo-service", targets: ["TempoService"]))
targets.append(.executableTarget(name: "TempoService", dependencies: ["TempoCore", "TempoInput"]))
#endif

let package = Package(name: "TempoTime", platforms: [.macOS(.v13)],
                      products: products, targets: targets, swiftLanguageModes: [.v5])
