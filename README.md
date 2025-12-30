# Hokusai

**Fast, hybrid image processing for Swift server-side applications**

Hokusai is a high-performance image processing library that combines the best of both worlds:
- **libvips** for blazing-fast operations (resize, crop, rotate, format conversion)
- **ImageMagick** for advanced text rendering with custom fonts, strokes, shadows, and typography controls

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

## How It Works

Hokusai provides a unified Swift API that automatically routes operations to the optimal backend:
- **ImageMagick (MagickWand)** - Advanced text rendering with custom fonts, strokes, shadows, and kerning
- **libvips** - High-performance image operations (resize, crop, rotate, convert)

The library handles backend switching transparently, converting between formats as needed via lossless PNG buffers.

## Installation

### Requirements

**macOS:**
```bash
brew install vips imagemagick pkg-config
```

**Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install libvips-dev libmagick++-dev libmagickwand-dev pkg-config
```

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/ivantokar/hokusai.git", from: "0.1.0")
]

targets: [
    .target(
        name: "YourTarget",
        dependencies: ["Hokusai"]
    )
]
```

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
// Initialize both libvips and ImageMagick
try Hokusai.initialize()

// Shutdown when done (call at app teardown)
Hokusai.shutdown()

// Get version info
print(Hokusai.vipsVersion)    // "8.15.1"
print(Hokusai.magickVersion)  // "6.9.11-60"
```

### Loading Images

```swift
// From file path
let image = try await Hokusai.image(from: "/path/to/image.jpg")

// From Data buffer
let data = try Data(contentsOf: url)
let image = try await Hokusai.image(from: data)
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

### Backend Switching

Hokusai automatically routes operations to the optimal backend:

```
┌─────────────────────────────────────┐
│         HokusaiImage                │
│  (Unified API with Auto-Routing)    │
└──────────┬─────────────┬────────────┘
           │             │
    ┌──────▼──────┐ ┌───▼──────────┐
    │ VipsBackend │ │MagickBackend │
    │  (libvips)  │ │ (ImageMagick)│
    └─────────────┘ └──────────────┘
         │                │
    ┌────▼────┐      ┌───▼──────┐
    │  Resize │      │   Text   │
    │  Crop   │      │ Rendering│
    │  Rotate │      │          │
    │ Convert │      │          │
    │Composite│      │          │
    └─────────┘      └──────────┘
```

**Conversion Strategy:**
- Operations on the same backend: Zero overhead
- Backend switching: Lossless PNG buffer conversion (< 50ms typical)
- Memory efficient: Only one backend active at a time

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

### Benchmarks (3206x2266 image on M1 Mac)

| Operation | Time | Memory |
|-----------|------|--------|
| Load JPEG | 45ms | 28MB |
| Resize 800px | 12ms | 3MB |
| Rotate 90° | 8ms | 28MB |
| Text overlay | 35ms | 32MB |
| Save JPEG (q=85) | 28ms | - |
| Backend switch | 42ms | 28MB |

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

Hokusai runs on macOS/Linux (libvips + ImageMagick) and is intended for server use. iOS apps should call a HokusaiVapor server instead.

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
} catch HokusaiError.magickError(let message) {
    print("ImageMagick error: \(message)")
} catch {
    print("Unexpected error: \(error)")
}
```

## Platform-Specific Notes

### macOS
- ImageMagick 7 installed via Homebrew
- Headers at `/opt/homebrew/include/ImageMagick-7/`
- Supports both file paths and font names

### Linux (Ubuntu/Debian)
- ImageMagick 6 from apt
- Headers at `/usr/include/ImageMagick-6/`
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
swift test
```

Tests use Swift Testing (Swift 6+).
If your Swift 6 toolchain does not ship the `Testing` module yet, keep the `swift-testing` package dependency.

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
- [ImageMagick](https://imagemagick.org/) - Advanced image manipulation
- Inspired by [sharp](https://sharp.pixelplumbing.com/) (Node.js)

## Related Projects

- [hokusai-vapor](https://github.com/ivantokar/hokusai-vapor) - Vapor framework integration
- [hokusai-vapor-example](https://github.com/ivantokar/hokusai-vapor-example) - Complete demo app with web UI
