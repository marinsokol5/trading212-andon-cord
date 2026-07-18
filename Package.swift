// swift-tools-version: 6.0
import PackageDescription

/// Trading212 Andon Cord is intentionally one package with two trust domains:
///
/// - `AndonApp` links only `Trading212Core`, so the GUI binary contains no
///   order-placement implementation.
/// - `t212` links both libraries and is the only user-facing executable that
///   can place orders.
let package = Package(
    name: "Trading212AndonCord",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "Trading212Core", targets: ["Trading212Core"]),
        .library(name: "Trading212Trading", targets: ["Trading212Trading"]),
        .executable(name: "AndonApp", targets: ["AndonApp"]),
        .executable(name: "t212", targets: ["andon"]),
    ],
    targets: [
        .target(
            name: "Trading212Core",
            linkerSettings: [
                .linkedFramework("Security"),
            ]),
        .target(
            name: "Trading212Trading",
            dependencies: ["Trading212Core"],
            linkerSettings: [
                .linkedFramework("LocalAuthentication"),
                .linkedFramework("Security"),
            ]),
        .executableTarget(
            name: "AndonApp",
            dependencies: ["Trading212Core"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
            ]),
        .executableTarget(
            name: "andon",
            dependencies: ["Trading212Core", "Trading212Trading"]),
        .testTarget(
            name: "Trading212CoreTests",
            dependencies: ["Trading212Core"]),
        .testTarget(
            name: "Trading212TradingTests",
            dependencies: ["Trading212Trading", "Trading212Core", "andon"]),
    ],
    swiftLanguageModes: [.v6])
