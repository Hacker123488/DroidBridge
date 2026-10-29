// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DroidBridge",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "DroidBridgeCore",
            targets: ["DroidBridgeCore"]
        ),
        .executable(
            name: "DroidBridgeApp",
            targets: ["DroidBridgeApp"]
        ),
        .executable(
            name: "DroidBridgeTestRunner",
            targets: ["DroidBridgeTestRunner"]
        )
    ],
    targets: [
        .target(
            name: "DroidBridgeCore",
            path: "src/DroidBridgeCore"
        ),
        .executableTarget(
            name: "DroidBridgeApp",
            dependencies: ["DroidBridgeCore"],
            path: "src/DroidBridgeApp"
        ),
        .executableTarget(
            name: "DroidBridgeTestRunner",
            dependencies: ["DroidBridgeCore"],
            path: "tests/DroidBridgeTestRunner"
        )
    ]
)
