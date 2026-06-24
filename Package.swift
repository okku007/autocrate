// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Autocrate",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AutocrateCore", targets: ["AutocrateCore"]),
        .library(name: "AutocrateAppKit", targets: ["AutocrateAppKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0")
    ],
    targets: [
        .target(
            name: "AutocrateCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        // App-side logic (Theme/Music/UI/Pipeline coordinator). Compile-checked headlessly;
        // the macOS app target in Xcode is a thin @main + Info.plist shell that imports this.
        .target(
            name: "AutocrateAppKit",
            dependencies: ["AutocrateCore"]
        ),
        .testTarget(
            name: "AutocrateCoreTests",
            dependencies: ["AutocrateCore"]
        )
    ]
)
