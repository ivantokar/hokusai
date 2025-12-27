# Hokusai

A hybrid Swift image processing library combining the power of **ImageMagick** for advanced text rendering and **libvips** for high-performance image operations.

[![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org)
[![Platform](https://img.shields.io/badge/Platform-macOS%20|%20Linux-lightgrey.svg)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

## Overview

Hokusai provides a unified Swift API that automatically routes operations to the optimal backend:
- **ImageMagick (MagickWand)** - Advanced text rendering with custom fonts, strokes, shadows, and kerning
- **libvips** - High-performance image operations (resize, crop, rotate, convert)

The library handles backend switching transparently, converting between formats as needed via lossless PNG buffers.

## Features

### Text Rendering (ImageMagick)
- ✅ Custom TrueType/OpenType fonts via file path or system font name
- ✅ Text stroke (outline) with configurable width and color
- ✅ Advanced typography: font size, color, kerning, rotation
- ✅ High-quality antialiasing

### Image Operations (libvips)
- ✅ **Resize** - Multiple fit modes (fill, contain, cover, inside, outside)
- ✅ **Crop** - Manual and smart cropping with attention detection
- ✅ **Rotate** - Fast 90° rotations and arbitrary angle rotation
- ✅ **Convert** - Support for JPEG, PNG, WebP, AVIF, GIF, TIFF formats
- ✅ **Metadata** - Extract dimensions, format, color space, EXIF data

### Architecture
- 🔄 Automatic backend switching based on operation type
- 🚀 Streaming processing keeps memory usage low (libvips)
- 🔒 Thread-safe with NSLock protection
- 🎯 Fluent, chainable API
- 📦 Single unified `HokusaiImage` type

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
    .package(url: "https://github.com/yourusername/hokusai.git", from: "1.0.0")
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
let rotated90 = try image.rotate(angle: .d90)
let rotated180 = try image.rotate(angle: .d180)
let rotated270 = try image.rotate(angle: .d270)

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

### Metadata

```swift
let metadata = try image.metadata()

print(metadata.width)      // 3206
print(metadata.height)     // 2266
print(metadata.channels)   // 4 (RGBA)
print(metadata.hasAlpha)   // true
print(metadata.format)     // Optional(ImageFormat.jpeg)
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
See the [hokusai-vapor](../hokusai-vapor) package for Docker deployment examples.

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
- Inspired by [sharp](https://sharp.pixelplumbing.com/) (Node.js) and [vips-kit](https://github.com/yourusername/vips-kit)

## Related Projects

- [hokusai-vapor](../hokusai-vapor) - Vapor framework integration
- [vips-kit](../vips-kit) - Pure libvips Swift wrapper
