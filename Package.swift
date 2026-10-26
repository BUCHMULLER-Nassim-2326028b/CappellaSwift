// swift-tools-version: 5.10
import Foundation
import PackageDescription

var products: [Product] = [.library(name: "CappellaCore", targets: ["CappellaCore"])]
var dependencies: [Package.Dependency] = []
var targets: [Target] = [
    .target(name: "CappellaCore"),
    .testTarget(name: "CappellaCoreTests", dependencies: ["CappellaCore"])
]
#if os(macOS)
products.append(.executable(name: "CappellaMac", targets: ["CappellaMac"]))
targets += [
    .target(name: "CappellaSession", dependencies: ["CappellaCore"]),
    .executableTarget(name: "CappellaMac", dependencies: ["CappellaCore", "CappellaSession"], linkerSettings: [.linkedFramework("AVKit")]),
    .testTarget(name: "CappellaSessionTests", dependencies: ["CappellaCore", "CappellaSession"])
]
#elseif os(Windows)
// Core tests can run without downloading/generating the UI projections.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
if FileManager.default.fileExists(atPath: root.appendingPathComponent(".windows/Projections/Package.swift").path) {
    dependencies.append(.package(path: ".windows/Projections"))
    products.append(.executable(name: "CappellaWindows", targets: ["CappellaWindows"]))
    targets += [
        // Pixel conversion and audio loops must remain fast in Debug builds too.
        .target(name: "CWindowsInterop", cxxSettings: [.unsafeFlags(["-O2"])], linkerSettings: [.linkedLibrary("ole32"), .linkedLibrary("shell32"), .linkedLibrary("mfplat"), .linkedLibrary("mfreadwrite"), .linkedLibrary("mfuuid"), .linkedLibrary("dwrite"), .linkedLibrary("gdi32"), .linkedLibrary("user32")]),
        .executableTarget(name: "CappellaWindows", dependencies: ["CappellaCore", "CWindowsInterop",
            .product(name: "WinUI", package: "Projections"), .product(name: "UWP", package: "Projections"),
            .product(name: "WinAppSDK", package: "Projections"), .product(name: "WindowsFoundation", package: "Projections")
        ], linkerSettings: [
            // Debug information otherwise disables these standard COFF release
            // optimizations. Keep referenced Swift/WinRT metadata and factories.
            .unsafeFlags(["-Xlinker", "/OPT:REF", "-Xlinker", "/OPT:ICF"], .when(configuration: .release))
        ]),
        .testTarget(name: "CappellaWindowsTests", dependencies: ["CappellaCore", "CappellaWindows"])
    ]
}
#endif
let package = Package(name: "CappellaMac", platforms: [.macOS(.v13)], products: products, dependencies: dependencies, targets: targets)
