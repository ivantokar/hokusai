// swift-tools-version: 6.0
// PURPOSE: The swift-tools-version declares the minimum version of Swift required to build this package.

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
        .library(
            name: "HokusaiNIO",
            targets: ["HokusaiNIO"]
        ),
        .library(
            name: "HokusaiLegacy",
            targets: ["HokusaiLegacy"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        // 1.1.2+ required: earlier versions fail to compile on Linux (termios tcflag_t fix).
        .package(url: "https://github.com/ivantokar/prompt.git", from: "1.1.2"),
    ],
    targets: [
        // PURPOSE: System library wrapper for libvips
        .systemLibrary(
            name: "CVips",
            pkgConfig: "vips",
            providers: [
                .apt(["libvips-dev"]),
                .brew(["vips"]),
            ]
        ),
        .systemLibrary(
            name: "CCairo",
            pkgConfig: "cairo",
            providers: [
                .apt(["libcairo2-dev"]),
                .brew(["cairo"]),
            ]
        ),
        // PURPOSE: Main Hokusai library target
        .target(
            name: "Hokusai",
            dependencies: ["CVips", "CCairo"],
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
        .target(
            name: "HokusaiNIO",
            dependencies: [
                "Hokusai",
                .product(name: "NIOCore", package: "swift-nio"),
            ]
        ),
        .target(
            name: "HokusaiLegacy",
            dependencies: ["Hokusai"]
        ),
        // PURPOSE: Test target (library, CVips mapping, and CLI argument parsing)
        .testTarget(
            name: "HokusaiTests",
            dependencies: [
                "Hokusai",
                "HokusaiNIO",
                "HokusaiCLI",
                "CVips",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "NIOCore", package: "swift-nio"),
            ],
            resources: [
                .copy("Fixtures")
            ]
        ),
    ]
)
