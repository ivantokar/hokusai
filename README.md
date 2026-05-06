<p align="center">
<img src="./hokusai-logo-v3.png" alt="" width="400">
</p>

# Hokusai

**Fast, libvips-powered image processing for Swift server-side applications**

Hokusai is a high-performance image processing library built on **libvips** for blazing-fast operations (resize, crop, rotate, convert, composite) and text rendering via **Pango/Cairo through libvips**.
Built for modern Swift server applications with async/await support, comprehensive error handling, and a clean, chainable API.

[![Swift](https://img.shields.io/badge/Swift-6.0+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%20|%20Linux-lightgrey.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## Key Features

- **High Performance** - Streaming processing with minimal memory footprint via libvips
- **Advanced Text** - Professional text rendering with Google Fonts, stroke, shadow, kerning, rotation
- **Format Support** - JPEG, PNG, WebP, AVIF, GIF, TIFF with quality control
- **Smart Resizing** - Multiple fit modes (cover, contain, fill) with intelligent cropping
- **Compositing** - Layer images with blend modes and opacity control
- **Chainable API** - Fluent interface for combining operations
- **Type Safe** - Full Swift concurrency support with comprehensive error types

## Use Cases

- Certificate and badge generation with custom text
- Social media image automation (Open Graph, Twitter Cards)
- E-commerce product image pipelines
- Avatar and thumbnail generation
- Watermarking and branding workflows

## Related Projects

- [hokusai-vapor](https://github.com/ivantokar/hokusai-vapor) - Vapor framework integration
- [hokusai-vapor-example](https://github.com/ivantokar/hokusai-vapor-example) - Complete demo app with web UI

## How It Works

Hokusai provides a unified Swift API backed by libvips for all operations, including text rendering.

## Installation

### Requirements

- Swift 6.0+
- macOS 13+ or Linux (Ubuntu/Debian tested)
- `pkg-config` plus the native libraries below

**macOS:**
```bash
brew install vips pkg-config
```

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install libvips-dev pkg-config
```

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ivantokar/hokusai.git", from: "0.2.0")
]

targets: [
    .target(
        name: "YourTarget",
        dependencies: ["Hokusai"]
    )
]
```

## CLI

Hokusai ships with a first-party CLI target: `hokusai`.

### Run from source

```bash
swift run hokusai --help
swift run hokusai info
swift run hokusai inspect --input ./input.jpg
swift run hokusai resize --input ./input.jpg --output ./out.jpg --width 1200 --height 800 --fit cover

# Thumbnail — optimised load+resize with EXIF auto-rotation
swift run hokusai thumbnail --input ./photo.jpg --output ./thumb.jpg --width 400
swift run hokusai thumbnail --input ./photo.jpg --output ./thumb.jpg --width 400 --height 300 --crop attention

# Benchmarks
swift run hokusai benchmark suite --input ./photo.jpg                      # full suite
swift run hokusai benchmark thumbnail --input ./photo.jpg --width 400 --height 300  # resize vs thumbnail comparison
swift run hokusai benchmark webp --input ./photo.jpg --concurrency-sweep   # WebP effort/concurrency sweep
```

### Install via Homebrew (recommended for users)

Use a dedicated tap repository (recommended: `ivantokar/homebrew-tap`) with a `hokusai` formula.

```bash
brew tap ivantokar/homebrew-tap
brew install hokusai
hokusai --help
```

If you have not published the formula yet, use `swift run hokusai ...` until the tap is live.

## Quick Start

```swift
import Hokusai

// Initialize Hokusai (call once at app startup)
try Hokusai.initialize()
defer { Hokusai.shutdown() }

// Load an image
let image = try await Hokusai.image(from: "photo.jpg")

// Chain operations
let processed = try image
    .resize(width: 800)
    .rotate(angle: .degrees(90))
    .drawText(
        "Hello World",
        x: 100,
        y: 100,
        options: TextOptions(
            font: "/path/to/font.ttf",
            fontSize: 48,
            color: [255, 255, 255, 255],
            strokeColor: [0, 0, 0, 255],
            strokeWidth: 2.0
        )
    )

// Save result
try processed.toFile("output.jpg", quality: 85)
```

## API Documentation

### Initialization

```swift
// Initialize libvips backend
try Hokusai.initialize()

// Shutdown when done (call at app teardown)
Hokusai.shutdown()

// Get version info
print(Hokusai.vipsVersion)    // "8.15.1"
```

### Loading Images

```swift
// From file path
let image = try await Hokusai.image(from: "/path/to/image.jpg")

// From Data buffer
let data = try Data(contentsOf: url)
let image = try await Hokusai.image(from: data)

// Sequential access — lower peak memory for large single-pass pipelines
// Not recommended for JPEG downscaling (disables shrink-on-load)
let image = try await Hokusai.image(from: "/path/to/image.jpg", options: .sequential)
```

### Text Rendering

```swift
var textOptions = TextOptions()
textOptions.font = "/path/to/CustomFont.ttf"  // or "Arial" for system fonts
textOptions.fontSize = 96
textOptions.color = [0, 0, 128, 255]          // Navy blue (RGBA)
textOptions.strokeColor = [255, 255, 255, 255] // White outline
textOptions.strokeWidth = 2.0
textOptions.kerning = 1.5                      // Letter spacing
textOptions.rotation = 45.0                    // Rotate text 45°

let withText = try image.drawText(
    "Your Text Here",
    x: 200,
    y: 150,
    options: textOptions
)
```

### Thumbnail

`Hokusai.thumbnail(from:width:options:)` calls `vips_thumbnail()` internally. It applies EXIF auto-rotation by default and integrates smart cropping in a single pass. For cold-file-cache scenarios it reads less data from disk for JPEG, TIFF, and HEIF sources.

Use `resize` when you need explicit kernel control or fit modes like `contain`. Use `thumbnail` when you want auto-rotation and optional smart crop out of the box.

```swift
// Thumbnail from file — EXIF auto-rotation applied automatically
let thumb = try Hokusai.thumbnail(from: "photo.jpg", width: 400)

// With height constraint (fit inside 400×300, aspect ratio preserved)
let opts = ThumbnailOptions(height: 300)
let thumb = try Hokusai.thumbnail(from: "photo.jpg", width: 400, options: opts)

// Smart crop to exact dimensions
let cropped = try Hokusai.thumbnail(
    from: "photo.jpg",
    width: 400,
    options: ThumbnailOptions(height: 300, crop: .attention)
)

// From buffer
let thumb = try Hokusai.thumbnail(from: imageData, width: 400)

// On an already-loaded image (no shrink-on-load benefit, but same API)
let thumb = try image.thumbnail(width: 400)
```

### Resize Operations

```swift
// Resize to exact dimensions (ignores aspect ratio)
let resized = try image.resize(width: 800, height: 600)

// Resize to fit within dimensions (preserves aspect ratio)
let fitted = try image.resizeToFit(width: 800, height: 600)

// Resize to cover dimensions (crop to fill)
let covered = try image.resizeToCover(width: 800, height: 600)

// Advanced options
var options = ResizeOptions()
options.fit = .contain                // Fit mode: fill, inside, outside, cover, contain
options.kernel = .lanczos3            // Interpolation: nearest, linear, cubic, lanczos3
options.withoutEnlargement = true     // Don't upscale
options.background = [0, 0, 0, 255]   // Background color for contain mode

let resized = try image.resize(width: 800, height: 600, options: options)
```

### Crop Operations

```swift
// Manual crop
let cropped = try image.crop(x: 100, y: 100, width: 500, height: 400)

// Smart crop (attention detection)
let smartCropped = try image.smartCrop(
    width: 400,
    height: 400,
    position: .center  // or .top, .bottom, .left, .right, etc.
)
```

### Rotation

```swift
// Fast 90° rotations
let rotated90 = try image.rotate(angle: .degree90)
let rotated180 = try image.rotate(angle: .degree180)
let rotated270 = try image.rotate(angle: .degree270)

// Arbitrary angle
let rotated = try image.rotate(
    angle: .degrees(45),
    background: [255, 255, 255, 255]  // White background
)

// Flip
let flipped = try image.flip(direction: .horizontal)  // or .vertical, .both
```

### Format Conversion

```swift
// Convert and save
try image.toFile("output.png")
try image.toFile("output.webp", quality: 80)
try image.toFile("output.avif", quality: 75)

// Convert to buffer
let jpegData = try image.toBuffer(format: "jpeg", quality: 85)
let pngData = try image.toBuffer(format: "png", quality: 9)
let webpData = try image.toBuffer(format: "webp", quality: 80)
```

AVIF/HEIF output requires libvips built with libheif support.

### Composite / Watermark

```swift
let base = try await Hokusai.image(from: "photo.jpg")
let overlay = try await Hokusai.image(from: "watermark.png")

let options = CompositeOptions(mode: .over, opacity: 0.6)
let composited = try base.composite(
    overlay: overlay,
    x: 16,
    y: 16,
    options: options
)

try composited.toFile("watermarked.png")
```

### Metadata

```swift
let metadata = try image.metadata()

print(metadata.width)      // 3206
print(metadata.height)     // 2266
print(metadata.channels)   // 4 (RGBA)
print(metadata.hasAlpha)   // true
print(metadata.format)     // Optional(ImageFormat.jpeg) (may be nil)
```

### Direct Property Access

```swift
let width = try image.width
let height = try image.height
let channels = try image.bands
let hasAlpha = try image.hasAlpha
```

## Architecture

### Single Backend

```
┌─────────────────────────────────────┐
│            HokusaiImage             │
│      (Unified API, libvips only)    │
└──────────────────┬──────────────────┘
                   │
            ┌──────▼──────┐
            │ VipsBackend │
            │  (libvips)  │
            └─────────────┘
                   │
            ┌──────▼──────┐
            │ Resize/Crop │
            │ Rotate/Text │
            │ Convert/Comp│
            └─────────────┘
```

All operations are executed by libvips, with text rendering powered by Pango/Cairo through `vips_text`.

### Thread Safety

All operations are thread-safe using NSLock:
```swift
let operations = (0..<10).map { i in
    Task {
        let image = try await Hokusai.image(from: "input.jpg")
        let processed = try image
            .resize(width: 800)
            .drawText("Frame \(i)", x: 10, y: 10)
        try processed.toFile("output_\(i).jpg")
    }
}
await withTaskGroup(of: Void.self) { group in
    operations.forEach { group.addTask { try? await $0.value } }
}
```

## Performance

### Benchmarks (measured with `hokusai benchmark suite`)

Environment: Apple M4 Pro · macOS · libvips 8.18.2 · 12 cores · release binary · 3 warmup + 25 measured iterations

**Small source (1000×800 JPEG, warm file cache)**

| Case | Mean | Median | P95 | Min | Max | Ops/s |
|------|-----:|-------:|----:|----:|----:|------:|
| resize:default:1200x800 | 3.84 ms | 3.80 ms | 4.28 ms | 3.38 ms | 4.29 ms | 260 |
| thumbnail:file:1200x800 | 4.26 ms | 4.28 ms | 4.47 ms | 3.84 ms | 4.51 ms | 235 |
| thumbnail:file:1200 | 5.12 ms | 4.99 ms | 5.85 ms | 4.65 ms | 6.14 ms | 195 |
| resize:sequential:1200x800 | 4.50 ms | 4.49 ms | 4.85 ms | 4.15 ms | 5.06 ms | 222 |
| convert:webp:q80 | 37.65 ms | 37.67 ms | 38.18 ms | 36.84 ms | 38.34 ms | 27 |
| rotate:33 | 3.14 ms | 3.16 ms | 3.34 ms | 2.93 ms | 3.47 ms | 319 |
| text:stroke-shadow | 57.52 ms | 57.51 ms | 59.42 ms | 55.43 ms | 59.56 ms | 17 |

**Large source (4000×3200 JPEG, warm file cache, 3 warmup + 20 iterations)**

| Case | Op path | Access | Mean | Median | P95 | Ops/s |
|------|---------|--------|-----:|-------:|----:|------:|
| resize:default | vips_resize | random | 2.73 ms | 2.69 ms | 3.06 ms | 366 |
| thumbnail:file | vips_thumbnail | n/a | 10.01 ms | 9.98 ms | 10.24 ms | 100 |
| thumbnail:image | vips_thumbnail_image | random | 2.84 ms | 2.80 ms | 3.20 ms | 352 |
| resize:sequential | vips_resize | sequential | 21.74 ms | 21.67 ms | 22.78 ms | 46 |

**Key observations**

- On warm-cache benchmarks, `resize:default` (random access + vips_resize) was fastest across all test cases. libvips's internal pipeline handles JPEG shrink-on-load automatically for random-access loads.
- `vips_thumbnail` from a file path adds overhead (header inspection, second open) that hurts throughput on cached files. Its advantage appears in cold-cache or storage-bound scenarios.
- Sequential access was 8× slower for JPEG downscaling. It disables the JPEG decoder's shrink-on-load optimisation. Do not use it for JPEG sources being heavily downscaled.
- `thumbnail:image` (on an already-decoded image) is comparable to `resize:default` since file I/O is not in the picture.

These results are machine-specific and cache-state dependent. Reproduce them on your hardware with `hokusai benchmark suite` and `hokusai benchmark thumbnail`.

### WebP encoding

Input: `2.webp` (800x450, RGB) — libvips 8.18.2 — Apple M4 Pro — 12 cores

**Format comparison** (`toBuffer`, same input):

| Case | Mean | P95 | Ops/s |
| --- | ---: | ---: | ---: |
| jpeg:q80 | 1.13 ms | 1.21 ms | 881 |
| webp:q80:effort0 | 6.13 ms | 6.31 ms | 163 |
| webp:q80:effort2 | 10.28 ms | 11.16 ms | 97 |
| webp:q80:effort4 (default) | 20.07 ms | 20.50 ms | 50 |
| png:compression6 | 25.58 ms | 26.11 ms | 39 |
| webp:q80:effort6 | 38.26 ms | 38.57 ms | 26 |
| webp:lossless:effort4 | 172.58 ms | 175.47 ms | 6 |

**`effort` impact on webp:q80** (0 = fastest encoder, 6 = smallest file):

| effort | Mean | Ops/s | vs effort4 |
| --- | ---: | ---: | ---: |
| 0 | 6.13 ms | 163 | 3.3× faster |
| 2 | 10.28 ms | 97 | 2.0× faster |
| 4 | 20.07 ms | 50 | baseline |
| 6 | 38.26 ms | 26 | 1.9× slower |

**Concurrency** (`vips_concurrency_set`, webp:q80:effort4):

| Concurrency | Mean |
| --- | ---: |
| 1 | 20.16 ms |
| 4 | 20.20 ms |
| 12 | 20.42 ms |

The libvips concurrency setting does not affect single-image WebP encode time. libvips threads
parallelise the image pipeline (e.g. resize, rotate); the libwebp encode call itself is
sequential per image. `effort` is the primary knob for trading encode speed against file size.

Run `hokusai benchmark webp --input <file> [--concurrency-sweep]` to reproduce on your hardware.

### Memory Management

- libvips processes images in chunks (streaming)
- Typical memory usage: 1.5x - 2x of output image size
- Automatic cleanup via `deinit`
- No manual memory management required

## Advanced Usage

### Custom Font Loading

```swift
// System fonts (by name)
let options1 = TextOptions(font: "Arial")
let options2 = TextOptions(font: "Helvetica-Bold")

// Custom fonts (by path)
let options3 = TextOptions(font: "/usr/share/fonts/truetype/MyFont.ttf")
let options4 = TextOptions(font: "./assets/CustomFont.otf")

// On Linux, use fontconfig names
let options5 = TextOptions(font: "DejaVu Sans")
let options6 = TextOptions(font: "Liberation Serif")
```

### iOS Client Example

Hokusai runs on macOS/Linux (libvips) and is intended for server use. iOS apps should call a HokusaiVapor server instead.

This example calls the HokusaiVapor `/api/images/convert` endpoint from an iOS app:

```swift
import UIKit

func convertToWebP(_ image: UIImage, baseURL: URL) async throws -> UIImage {
    guard let data = image.jpegData(compressionQuality: 0.9) else {
        throw URLError(.cannotDecodeRawData)
    }

    var components = URLComponents(
        url: baseURL.appendingPathComponent("api/images/convert"),
        resolvingAgainstBaseURL: false
    )
    components?.queryItems = [
        URLQueryItem(name: "format", value: "webp"),
        URLQueryItem(name: "quality", value: "80")
    ]

    guard let url = components?.url else {
        throw URLError(.badURL)
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
    request.httpBody = data

    let (responseData, _) = try await URLSession.shared.data(for: request)
    guard let processed = UIImage(data: responseData) else {
        throw URLError(.cannotDecodeRawData)
    }

    return processed
}
```

### Error Handling

```swift
do {
    let image = try await Hokusai.image(from: "input.jpg")
    let processed = try image.resize(width: 800)
    try processed.toFile("output.jpg")
} catch HokusaiError.fileNotFound(let path) {
    print("Image not found: \(path)")
} catch HokusaiError.loadFailed(let message) {
    print("Failed to load image: \(message)")
} catch HokusaiError.vipsError(let message) {
    print("libvips error: \(message)")
} catch {
    print("Unexpected error: \(error)")
}
```

## Platform-Specific Notes

### macOS
- Install libvips via Homebrew (`brew install vips`)

### Linux (Ubuntu/Debian)
- Install libvips via apt (`sudo apt install libvips-dev`)
- Use fontconfig font names or absolute paths

### Docker
See the [hokusai-vapor-example](https://github.com/ivantokar/hokusai-vapor-example) demo app for a complete Docker deployment example.

## Troubleshooting

### pkg-config errors

**macOS:**
```bash
export PKG_CONFIG_PATH=/opt/homebrew/lib/pkgconfig
```

**Linux:**
```bash
export PKG_CONFIG_PATH=/usr/lib/$(uname -m)-linux-gnu/pkgconfig
```

### Font not found errors

**Verify font installation:**
```bash
# List available fonts
fc-list | grep "YourFont"

# Update font cache
fc-cache -f -v
```

**Use absolute paths:**
```swift
// Instead of font name
textOptions.font = "MyCustomFont"

// Use absolute path
textOptions.font = "/usr/share/fonts/truetype/MyCustomFont.ttf"
```

## Testing

```bash
swift build
swift test
```

Tests are implemented with `XCTest` and run with standard SwiftPM tooling.
The package keeps a minimal `swift-testing` dependency to support toolchains where SwiftPM still expects the `Testing` module at test runtime.

## Releases

Hokusai follows semantic version tags in the format `vX.Y.Z`.

- Releases are managed manually via semantic version tags (`vX.Y.Z`).
- This repository intentionally does not run GitHub Actions workflows to reduce OSS costs.
- Human-curated release notes are tracked in [CHANGELOG.md](CHANGELOG.md).

## Swift Package Index

This repository is structured to be compatible with Swift Package Index:

- semantic version tags (`vX.Y.Z`)
- local validation with `swift build` and `swift test`
- clear installation/usage docs in this README

Recommended next step when API docs grow: add a lightweight DocC catalog at `Sources/Hokusai/Hokusai.docc` and let SPI host the generated documentation.

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass
5. Submit a pull request

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Credits

Built with:
- [libvips](https://www.libvips.org/) - Fast image processing library
- Inspired by [sharp](https://sharp.pixelplumbing.com/) (Node.js)
