<p align="center">
<img src="./hokusai-logo-v4.png" alt="Hokusai — Swift image processing library" width="500">
</p>

# Hokusai

## High-performance Swift image processing

Hokusai is a Swift image-processing library powered by [libvips](https://www.libvips.org/) for server-side applications. It provides a clear, immutable pipeline API: build a recipe synchronously, then evaluate it with an asynchronous output terminal.

libvips processes images on demand, using small regions of pixel data at a time and available CPU cores efficiently. Hokusai exposes that capability through Swift without spawning child processes.

## Requirements

- Swift 6.0+
- macOS 13+ or Ubuntu/Debian Linux
- libvips 8.9+, Cairo PDF support, and `pkg-config`

```bash
# macOS
brew install vips cairo pkg-config

# Ubuntu/Debian
sudo apt update
sudo apt install libvips-dev libcairo2-dev pkg-config
```

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/ivantokar/hokusai.git", from: "1.0.0")
]
```

Add `Hokusai` to your target dependencies. Optional products are `HokusaiNIO` for `ByteBuffer` bridging and `HokusaiLegacy` for temporary 0.x migration support.

## Quick start

```swift
import Hokusai

let output = try await Hokusai(url: URL(fileURLWithPath: "photo.jpg"))
    .autoOrient()
    .resize(width: 1200, height: 630, fit: .cover, position: .attention)
    .webp(quality: 82)
    .write(to: URL(fileURLWithPath: "social-card.webp"))

print("Wrote \(output.width) × \(output.height)")
```

## Inputs and output terminals

```swift
let fromData = try Hokusai(data: uploadData)
let fromFile = try Hokusai(url: URL(fileURLWithPath: "photo.jpg"))

let jpeg = try await fromData.jpeg(quality: 85).data()
let png = try await fromData.png(compressionLevel: 6).data()
let info = try await fromFile.write(to: URL(fileURLWithPath: "output.webp"))
```

`data()` and `write(to:)` run the blocking native work off Swift's cooperative executor. Pipelines are immutable and safe to branch across tasks.

## Transformations

```swift
let base = try Hokusai(url: URL(fileURLWithPath: "photo.jpg"))
let logo = try Hokusai(url: URL(fileURLWithPath: "logo.png"))

var label = TextOptions(font: "sans Bold", fontSize: 48, color: [255, 255, 255, 255])
label.strokeColor = [0, 0, 0, 255]
label.strokeWidth = 2

let image = try base
    .resize(width: 1200, height: 800, fit: .cover)
    .composite([CompositeLayer(logo, x: 32, y: 32, opacity: 0.8)])
    .drawText("Hello, Hokusai", x: 80, y: 680, options: label)
    .flatten(background: .white)
```

Core operations include resize, extract, rotate, auto-orient, composite, blur, sharpen, trim, tint, flatten/remove alpha, metadata inspection, and typed JPEG/PNG/WebP/AVIF output.

## PDF output

```swift
let pdf = try await Hokusai(url: URL(fileURLWithPath: "photo.jpg"))
    .resize(width: 1240)
    .pdf(pageSize: .a4, dpi: 150)
    .write(to: URL(fileURLWithPath: "report.pdf"))
```

PDF output is Cairo-backed and contains the evaluated raster pipeline on one page. It is suitable for generated image reports and layered compositions, but does not currently preserve selectable vector text. The planned Swift API for vector PDF scenes is tracked in [#13](https://github.com/ivantokar/hokusai/issues/13).

## Runtime lifecycle

Loading a pipeline initializes the runtime automatically. Call `Hokusai.initialize()` at application startup only if you want startup failures surfaced explicitly.

Do not call `Hokusai.shutdown()` in a normal server or application lifecycle. It is a final process-teardown operation for short-lived tools after all native images have been released.

## CLI

```bash
swift run hokusai inspect --input photo.jpg
swift run hokusai resize --input photo.jpg --output social.webp --width 1200 --height 630 --fit cover
swift run hokusai convert --input photo.jpg --output photo.pdf
swift run hokusai thumbnail --input photo.jpg --output thumb.jpg --width 400
```

The optimized `thumbnail` CLI command currently uses the intentionally retained legacy thumbnail loader while its public 1.0 pipeline counterpart is designed.

## 0.x migration

| 0.x adapter API | 1.0 pipeline API |
| --- | --- |
| `Hokusai.image(from: path)` | `Hokusai(url: URL(fileURLWithPath: path))` |
| `Hokusai.image(from: data)` | `Hokusai(data: data)` |
| `image.resize(...).toFile(path)` | `try await pipeline.resize(...).write(to: URL(...))` |
| `image.crop(...)` | `pipeline.extract(x:y:width:height:)` |
| `image.toBuffer(...)` | Select `.jpeg()` / `.png()` / `.webp()` / `.avif()`, then `try await .data()` |

Import `HokusaiLegacy` only as a temporary adapter during migration.

## Related projects

- [Hokusai Vapor](https://github.com/ivantokar/hokusai-vapor)
- [Archived Vapor example](https://github.com/ivantokar/hokusai-vapor-example)
- [API documentation](Sources/Hokusai/Hokusai.docc/Hokusai.md)
