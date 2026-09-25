// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DaVinciCleaner",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "DaVinciCleaner", targets: ["DaVinciCleaner"]),
        .library(name: "CleanerCore", targets: ["CleanerCore"]),
    ],
    targets: [
        // Pure Foundation engine: scanning, safety checks, removal, stats.
        // Kept free of SwiftUI/AppKit so it can be unit tested in isolation.
        .target(name: "CleanerCore"),
        // The SwiftUI macOS app.
        .executableTarget(
            name: "DaVinciCleaner",
            dependencies: ["CleanerCore"]
        ),
        .testTarget(
            name: "CleanerCoreTests",
            dependencies: ["CleanerCore"]
        ),
    ]
)
