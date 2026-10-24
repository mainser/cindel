// swift-tools-version: 5.9
import Foundation
import PackageDescription

// Match both Flutter's original Xcode integration and its framework package.
let flutterPackage = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().appendingPathComponent("../FlutterFramework/Package.swift")
let hasFlutterPackage = FileManager.default.fileExists(atPath: flutterPackage.path)

let package = Package(
    name: "cindel_flutter_libs",
    platforms: [.macOS("10.15")],
    products: [.library(name: "cindel-flutter-libs", targets: ["cindel_flutter_libs"])],
    dependencies: hasFlutterPackage
        ? [.package(name: "FlutterFramework", path: "../FlutterFramework")] : [],
    targets: [
        .binaryTarget(name: "CindelNative", path: "CindelNative.xcframework"),
        .target(
            name: "cindel_flutter_libs",
            dependencies: [.target(name: "CindelNative")] + (hasFlutterPackage
                ? [.product(name: "FlutterFramework", package: "FlutterFramework")] : [])
        )
    ]
)
