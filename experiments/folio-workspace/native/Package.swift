// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FolioNative",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "FolioCore", targets: ["FolioCore"]), .executable(name: "FolioNative", targets: ["FolioNative"])],
    targets: [
        .target(name: "FolioCore"),
        .executableTarget(name: "FolioNative", dependencies: ["FolioCore"], resources: [.copy("Resources/Math")]),
        .executableTarget(name: "FolioCoreChecks", dependencies: ["FolioCore"], path: "Tests/FolioCoreTests"),
    ],
    swiftLanguageModes: [.v5]
)
