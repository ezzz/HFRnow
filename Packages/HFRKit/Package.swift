// swift-tools-version: 6.2
import PackageDescription

// HFRKit is the UI-free engine of SwiftHFR: models, HTML parsing, networking, storage.
// Dependency direction is strict (see docs/ARCHITECTURE.md):
//   HFRModels  <-  HFRParsing
//   HFRModels  <-  HFRNetwork
//   HFRModels  <-  HFRStorage
// HFRParsing, HFRNetwork and HFRStorage must never depend on each other.
//   HFRModels + HFRParsing + HFRNetwork  <-  HFRClient   (multi-step flows, ADR 0008)
// HFRClient never depends on HFRStorage: the app passes stored values in and persists results.
let package = Package(
    name: "HFRKit",
    platforms: [
        .iOS("27.0"),
        .macOS("26.0")
    ],
    products: [
        .library(name: "HFRModels", targets: ["HFRModels"]),
        .library(name: "HFRParsing", targets: ["HFRParsing"]),
        .library(name: "HFRNetwork", targets: ["HFRNetwork"]),
        .library(name: "HFRStorage", targets: ["HFRStorage"]),
        .library(name: "HFRClient", targets: ["HFRClient"])
    ],
    dependencies: [
        // ADR 0002: SwiftSoup is the only HTML parser, used exclusively inside HFRParsing.
        .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.14.3")
    ],
    targets: [
        .target(name: "HFRModels", resources: [.process("Resources")]),
        .target(
            name: "HFRParsing",
            dependencies: [
                "HFRModels",
                .product(name: "SwiftSoup", package: "SwiftSoup")
            ]
        ),
        .target(name: "HFRNetwork", dependencies: ["HFRModels"]),
        .target(name: "HFRStorage", dependencies: ["HFRModels"]),
        .target(name: "HFRClient", dependencies: ["HFRModels", "HFRParsing", "HFRNetwork"]),

        .testTarget(name: "HFRModelsTests", dependencies: ["HFRModels"]),
        .testTarget(
            name: "HFRParsingTests",
            dependencies: ["HFRParsing"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "HFRNetworkTests", dependencies: ["HFRNetwork"]),
        .testTarget(name: "HFRStorageTests", dependencies: ["HFRStorage"]),
        .testTarget(name: "HFRClientTests", dependencies: ["HFRClient"])
    ],
    swiftLanguageModes: [.v6]
)
