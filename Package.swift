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
        )
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.7.0"),
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
        // System library wrapper for ImageMagick MagickWand
        .systemLibrary(
            name: "CImageMagick",
            pkgConfig: "MagickWand",
            providers: [
                .apt(["libmagick++-dev", "libmagickwand-dev"]),
                .brew(["imagemagick"]),
            ]
        ),
        // Main Hokusai library target
        .target(
            name: "Hokusai",
            dependencies: ["CVips", "CImageMagick"],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
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
