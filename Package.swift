// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "hokusai",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "Hokusai",
            targets: ["Hokusai"]
        ),
        .executable(
            name: "hokusai",
            targets: ["HokusaiCLI"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.7.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/ivantokar/prompt.git", from: "1.0.0"),
    ],
    targets: [
        // System library wrapper for libvips
        .systemLibrary(
            name: "CVips",
            pkgConfig: "vips",
            providers: [
                .apt(["libvips-dev"]),
                .brew(["vips"]),
            ]
        ),
        // Main Hokusai library target
        .target(
            name: "Hokusai",
            dependencies: ["CVips"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .executableTarget(
            name: "HokusaiCLI",
            dependencies: [
                "Hokusai",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Prompt", package: "prompt"),
            ]
        ),
        // Test target
        .testTarget(
            name: "HokusaiTests",
            dependencies: [
                "Hokusai",
                .product(name: "Testing", package: "swift-testing"),
            ],
            resources: [
                .copy("Fixtures")
            ]
        ),
    ]
)
