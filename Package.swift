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
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.7.0"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.90.0"),
        // 1.1.2+ required: earlier versions fail to compile on Linux (termios tcflag_t fix).
        .package(url: "https://github.com/ivantokar/prompt.git", from: "1.1.2"),
    ],
    targets: [
        // PURPOSE: System library wrapper for libvips. The native baseline
        // (libvips >= 8.16, Cairo >= 1.16) is enforced at compile time by the
        // module headers because pkg-config targets cannot express versions.
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
            dependencies: ["CVips", "CCairo"]
        ),
        // PURPOSE: Everything the `hokusai` command does. Depends on the public
        // Hokusai module only, so a command cannot reach the native layer.
        .target(
            name: "HokusaiCommandLine",
            dependencies: [
                "Hokusai",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Prompt", package: "prompt"),
            ]
        ),
        // PURPOSE: The `hokusai` executable: a process entry point only.
        .executableTarget(
            name: "HokusaiCLI",
            dependencies: ["HokusaiCommandLine"]
        ),
        .target(
            name: "HokusaiNIO",
            dependencies: [
                "Hokusai",
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOFoundationCompat", package: "swift-nio"),
            ]
        ),
        // PURPOSE: Test target (library, CVips mapping, and CLI argument parsing)
        .testTarget(
            name: "HokusaiTests",
            dependencies: [
                "Hokusai",
                "HokusaiNIO",
                "HokusaiCommandLine",
                "CVips",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "NIOCore", package: "swift-nio"),
            ],
            resources: [
                .copy("Fixtures")
            ]
        ),
        // PURPOSE: Black-box suite. Imports only the public Hokusai module (no
        // @testable, no CVips) so it can verify documented behaviour alone.
        .testTarget(
            name: "HokusaiPublicTests",
            dependencies: ["Hokusai"]
        ),
    ]
)
