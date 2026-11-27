// swift-tools-version: 5.9
// Der iOS-Teil von tb_voice (#644, Paket 3b) — über Swift Package Manager
// wie alle Plugins der App (ios/CLAUDE.md), ohne CocoaPods.

import PackageDescription

let package = Package(
    name: "tb_voice",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "tb-voice", targets: ["tb_voice"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework")
    ],
    targets: [
        .target(
            name: "tb_voice",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework")
            ]
        )
    ]
)
