<p align="center">
<img src="./hokusai-logo-v4.png" alt="Hokusai — Swift image processing library" width="500">
</p>

# Hokusai

## High-performance Swift image processing

Hokusai is a Swift image-processing library powered by [libvips](https://www.libvips.org/) for server-side applications. It provides a clear, immutable pipeline API: build a recipe synchronously, then evaluate it with an asynchronous output terminal.

libvips processes images on demand, using small regions of pixel data at a time and available CPU cores efficiently. Hokusai exposes that capability through Swift without spawning child processes.

## Requirements

Required:

- Swift 6.0+ (tested with Swift 6.0 and 6.4)
- macOS 13+ or Linux
- libvips 8.16+ — older versions are rejected at compile time
- Cairo 1.16+ with PDF surface support
- `pkg-config`

```bash
# macOS
brew install vips cairo pkg-config

# Debian 13+ / Ubuntu 25.04+ (distro libvips 8.16+)
sudo apt update
sudo apt install libvips-dev libcairo2-dev pkg-config
```

Ubuntu 24.04 and Debian 12 ship libvips older than 8.16; on those releases
build libvips from a [release tarball](https://github.com/libvips/libvips/releases)
(see `.github/scripts/install-libvips.sh` for the configuration CI uses).

Build-dependent capabilities depend on how libvips was compiled, not on
Hokusai's package dependencies: HEIF/AVIF, JPEG XL, JPEG 2000, PDF input, SVG,
Pango text rendering, and other optional codecs. Run `hokusai info` to inspect
the runtime you actually installed.

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

Building a pipeline only records what to do. The source is opened and processed when `data()` or `write(to:)` runs, so invalid image bytes, missing files, and pixel-dependent errors are thrown by the terminal, not by `Hokusai(data:)` or the transform call. Option validation (dimensions, quality, colours) still happens immediately.

## Inputs and output terminals

```swift
let fromData = try Hokusai(data: uploadData)
let fromFile = try Hokusai(url: URL(fileURLWithPath: "photo.jpg"))

let jpeg = try await fromData.jpeg(quality: 85).data()
let png = try await fromData.png(compressionLevel: 6).data()
let info = try await fromFile.write(to: URL(fileURLWithPath: "output.webp"))
```

`data()` and `write(to:)` run the blocking native work off Swift's cooperative executor. Concurrent evaluations beyond the scheduler's limit wait as suspended tasks in FIFO order. Cancelling the calling task removes a waiting evaluation or asks libvips to stop a running one; either way the terminal throws `CancellationError`, and the pipeline can be evaluated again. Pipelines are immutable and safe to branch across tasks.

### Evaluation order

A pipeline means exactly the operations you wrote, in the order you wrote them. Hokusai may change *how* it runs them but never *what* they produce, so it only applies a short whitelist of equivalence-preserving rules: it skips operations that are provably the identity (a rotation by whole turns, compositing no layers), and within one `data()` or `write(to:)` it builds a source or layer that several parts of the pipeline share only once. It never reorders operations (a `trim` or smart crop stays where you put it), fuses resizes, selects `.sequential` access for you, or keeps results between evaluations; libvips' own operation cache is the only cache. Output metadata and encoder choices are not image operations: the last `.png()`/`.webp()`/`preserveMetadata()` wins, and a composite layer contributes only its image operations.

### Input options

`InputOptions` is the one policy for opening an encoded image, from `Data` or a local file URL:

```swift
let image = try Hokusai(
    data: upload,
    options: .init(
        failOn: .truncated,                                  // when decoder problems become errors
        page: 1,                                             // one page of a multi-page file
        limits: .init(maxBytes: 20_000_000, maxPixels: 50_000_000)
    )
)
```

- **When bytes are copied.** `Hokusai(data:)` keeps your `Data` (copy-on-write) and does no native work; mutating or releasing your own value afterwards is safe. The bytes are copied into libvips-owned storage when the terminal opens the source. Opening reads only the image header and builds a lazy source; pixels are decoded as the pipeline needs them. A missing file, corrupt data, or an exceeded limit is reported by the terminal.
- **Decoder failure level** (`failOn`): `.none` decodes whatever it can; `.truncated` fails on truncated files; `.error` also fails on decoder errors; `.warning` (the default, as in Sharp) also fails on decoder warnings, so it rejects slightly malformed but viewable images. Failures are `HokusaiError.decode`. Choose the level that matches how strict your application must be.
- **Access** (`access`): `.random` (default) allows any pixel order. `.sequential` streams top to bottom with lower peak memory for single-pass pipelines; operations that read out of order may fail with a decode error. Measure before using it: for heavily downscaled JPEGs it was slower in our benchmarks.
- **Pages** (`page`): selects exactly one zero-based page (TIFF, PDF, GIF, WebP, ...). Without it you get the first page. A page beyond the file's page count is an `invalidOption`; selecting a page other than 0 in a single-page format is `unsupported`. Page ranges, all-page loading, and animation are not supported yet.
- **Limits** (`limits`): `maxBytes` (default 512 MiB) is checked before `Data` is copied and against a file's size; `maxPixels` (default 268,402,689, i.e. 16383 × 16383) and `maxChannels` (default 8) are checked from the header before any pixels are decoded. Exceeding one throws `HokusaiError.resource`. Tighten them to your upload policy; native codec safety limits always remain in force.
- **Freshness** (`revalidate`): libvips caches recent file opens, so a file replaced at the same path may be served from cache. `revalidate: true` bypasses the cache for that open. It has no effect on `Data`, and Hokusai keeps no cache of its own.

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

## Runtime

libvips is process-scoped: Hokusai initializes it at most once and it stays available until the process exits. There is no teardown API; the operating system reclaims native resources at exit. Loading a pipeline initializes the runtime automatically; call `Hokusai.initialize()` at startup only to surface initialization failures early.

### Configuration

Runtime settings are process-wide and belong in application startup:

```swift
try Hokusai.configure(.init(
    maxConcurrentEvaluations: .fixed(4),  // pipelines evaluated at once
    maxQueuedEvaluations: 64,             // waiting pipelines before .resource
    vipsConcurrency: .fixed(2)            // libvips threads per image computation
))
```

`configure(_:)` may be called once. Configuration freezes at the first `initialize()`, `capabilities()`, or `data()`/`write(to:)`; building pipelines does not freeze it. Later calls throw.

The two concurrency settings are different resources. `maxConcurrentEvaluations` limits how many whole pipelines Hokusai runs at once, which bounds memory and latency; extra evaluations wait in FIFO order as suspended tasks. `vipsConcurrency` sets how many libvips worker threads one image computation may use. With both `.automatic`, Hokusai currently admits one evaluation per active processor and libvips uses its own default; these defaults will be tuned from benchmarks before the major release. `maxQueuedEvaluations` (unbounded by default) rejects new work with `HokusaiError.resource` (kind `.queuedEvaluations`) instead of retaining more source bytes in memory.

### Capabilities and status

```swift
let capabilities = try Hokusai.capabilities()
guard capabilities.canEncode(.avif) else { /* offer WebP instead */ }

let status = Hokusai.runtimeStatus
print(status.queuedEvaluations, status.activeEvaluations)
```

Codec availability depends on how libvips was built, not on Hokusai's package dependencies. AVIF is verified by encoding and decoding a tiny image. PDF input (libvips `pdfload`) and PDF output (Cairo) are reported separately. `hokusai info` prints the same report.

`runtimeStatus` never initializes libvips. Its counters describe Hokusai's evaluation scheduler; they do not measure libvips worker threads or memory allocated by codec libraries.

## Errors

Terminals throw `HokusaiError` for processing failures and Swift's `CancellationError` when the calling task is cancelled:

```swift
do {
    _ = try await image.webp().data()
} catch is CancellationError {
    // expected task cancellation
} catch let error as HokusaiError {
    switch error {
    case .invalidInput, .invalidOption: break   // caller mistake, fix the request
    case .unsupported: break                    // not available in this libvips build
    case .decode, .transform, .encode: break    // processing failed
    case .io: break                             // known file read/write failure
    case .resource: break                       // a configured limit rejected the work
    case .runtime: break                        // libvips initialization or internal failure
    }
}
```

Branch on the case, not on message text. `FailureContext` carries a Hokusai-owned `operation` label and `reason`, plus an optional native `diagnostic`. libvips keeps one error log for the whole process, so under concurrent failures the diagnostic may include other evaluations' messages; use it for logs only.

## CLI

```bash
hokusai inspect --input photo.jpg
hokusai resize --input photo.jpg --output social.webp --width 1200 --height 630 --fit cover
hokusai convert --input photo.jpg --output photo.pdf
hokusai thumbnail --input photo.jpg --output thumb.jpg --width 400
hokusai benchmark pipeline --input photo.jpg --sigma 50
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

## 1.0 ergonomics roadmap

Hokusai follows the useful parts of Sharp's server-side image-processing
ergonomics—clear input, fluent transforms, configured output, and useful
metadata—while keeping Swift-native value semantics and async/await. A checked
item is implemented and covered by the current package; an unchecked item is a
deliberate, tracked capability rather than an implied promise.

### Core pipeline

- [x] Immutable, `Sendable` pipelines that safely branch by assignment.
- [x] Encoded `Data`, local file `URL`, and optional SwiftNIO `ByteBuffer`
  inputs.
- [x] Fluent geometry, colour, alpha, text, and typed compositing transforms.
- [x] Async `data()` and `write(to:)` terminals with FIFO admission and cancellation that stops running libvips work.
- [x] Typed JPEG, PNG, WebP, AVIF, and single-page raster PDF output.
- [x] Typed header metadata plus privacy-safe metadata removal by default.
- [ ] [First-class pipeline thumbnails with shrink-on-load](https://github.com/ivantokar/hokusai/issues/20).
- [ ] [Complete page, decoder-failure, and upload-safety input controls](https://github.com/ivantokar/hokusai/issues/21).
- [ ] [Typed raw-pixel input and output](https://github.com/ivantokar/hokusai/issues/22).

### Output, metadata, and composition

- [ ] [Capability-aware TIFF, GIF, and HEIF output](https://github.com/ivantokar/hokusai/issues/23).
- [ ] [Statistics and granular EXIF, ICC, XMP, orientation, and density controls](https://github.com/ivantokar/hokusai/issues/24).
- [ ] [Gravity placement and a broader typed blend-mode set](https://github.com/ivantokar/hokusai/issues/25).
- [ ] [A staged set of advanced transforms](https://github.com/ivantokar/hokusai/issues/26), beginning with common server-side operations rather than a generic native wrapper.
- [ ] [A documented multi-page and animation contract](https://github.com/ivantokar/hokusai/issues/27).

### Server operation and migration

- [x] Idempotent, process-safe, one-way libvips initialization.
- [x] Concurrent pipeline evaluation and copied buffer-input ownership.
- [ ] [Runtime format capabilities, queue observability, and safe process-level configuration](https://github.com/ivantokar/hokusai/issues/28).
- [ ] [A clean 1.0-first public API boundary and semver-safe legacy retirement plan](https://github.com/ivantokar/hokusai/issues/29).
- [ ] [Correct the CLI thumbnail documentation to match its implementation](https://github.com/ivantokar/hokusai/issues/30).

### Intentional Swift differences

The roadmap does not copy Sharp mechanically. Hokusai deliberately does not
add mutable `clone()` calls because assignment creates a safe immutable branch.
It uses async/await instead of Node callbacks or streams, typed Swift options
instead of JavaScript option bags, and local inputs rather than remote URL
fetching. Deep-zoom/tile serving, unrestricted native-operation dispatch, and
animation encoding remain separate product decisions, not implicit promises of
the core pipeline.

## Related projects

- [Hokusai Vapor](https://github.com/ivantokar/hokusai-vapor)
- [Archived Vapor example](https://github.com/ivantokar/hokusai-vapor-example)
- [API documentation](Sources/Hokusai/Hokusai.docc/Hokusai.md)
