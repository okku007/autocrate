// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Autocrate",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AutocrateCore", targets: ["AutocrateCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0")
    ],
    targets: [
        .target(
            name: "AutocrateCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "AutocrateCoreTests",
            dependencies: ["AutocrateCore"]
        )
    ]
)
