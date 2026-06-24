// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Autocrate",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AutocrateCore", targets: ["AutocrateCore"]),
        .library(name: "AutocrateAppKit", targets: ["AutocrateAppKit"]),
        .executable(name: "autocrate-probe", targets: ["autocrate-probe"]),
        .executable(name: "autocrate-dsp-probe", targets: ["autocrate-dsp-probe"])
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
        // Headless integration probe: exercises the live ScriptingBridge / pipeline path
        // without the menu-bar UI, timing each stage to locate blocking. Not shipped.
        .executableTarget(
            name: "autocrate-probe",
            dependencies: ["AutocrateAppKit", "AutocrateCore"]
        ),
        // Phase 0 gate: runs the on-device DSP estimators against real Apple preview clips and
        // compares to known BPM/key. Pass the clip dir via CLIPS env or argv. Not shipped.
        .executableTarget(
            name: "autocrate-dsp-probe",
            dependencies: ["AutocrateCore"]
        ),
        .testTarget(
            name: "AutocrateCoreTests",
            dependencies: ["AutocrateCore"]
        )
    ]
)
