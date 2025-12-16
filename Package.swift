// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DetentScrollView",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "DetentScrollView", targets: ["DetentScrollView"])
    ],
    dependencies: [
        .package(path: "../Mercurial")
    ],
    targets: [
        .target(
            name: "DetentScrollView",
            dependencies: ["Mercurial"]
        ),
        .testTarget(
            name: "DetentScrollViewTests",
            dependencies: ["DetentScrollView"]
        )
    ]
)
