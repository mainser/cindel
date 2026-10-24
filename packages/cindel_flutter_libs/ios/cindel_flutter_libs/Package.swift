// swift-tools-version: 5.9
import Foundation
import PackageDescription

// Older Flutter versions supply Flutter through Xcode's framework search paths.
// Newer integrations can supply it as a sibling Swift package instead.
let flutterPackage = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().appendingPathComponent("../FlutterFramework/Package.swift")
let hasFlutterPackage = FileManager.default.fileExists(atPath: flutterPackage.path)

let package = Package(
    name: "cindel_flutter_libs",
    platforms: [.iOS("13.0")],
    products: [.library(name: "cindel-flutter-libs", targets: ["cindel_flutter_libs"])],
    dependencies: hasFlutterPackage
        ? [.package(name: "FlutterFramework", path: "../FlutterFramework")] : [],
    targets: [
        .binaryTarget(name: "CindelNative", path: "cindel.xcframework"),
        .target(
            name: "cindel_flutter_libs",
            dependencies: [.target(name: "CindelNative")] + (hasFlutterPackage
                ? [.product(name: "FlutterFramework", package: "FlutterFramework")] : []),
            publicHeadersPath: "include",
            cSettings: [.headerSearchPath("include/cindel_flutter_libs")],
            linkerSettings: [.linkedLibrary("iconv"), .linkedLibrary("resolv")]
        )
    ]
)
