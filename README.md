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

A pipeline means exactly the operations you wrote, in the order you wrote them. Hokusai may change *how* it runs them but never *what* they produce, so it only applies a short whitelist of equivalence-preserving rules: it skips operations that are provably the identity (a rotation by whole turns, compositing no layers), and within one `data()` or `write(to:)` it builds a source or layer that several parts of the pipeline share only once. It never reorders operations (a `trim` or smart crop stays where you put it), fuses resizes, selects `.sequential` access for you, or keeps results between evaluations; libvips' own operation cache is the only cache. Output metadata and encoder choices are not image operations: the last `.png()`/`.webp()`/`metadataPolicy(_:)` wins, and a composite layer contributes only its image operations.

### Output metadata

What encoded output keeps of the source's embedded metadata is a typed `MetadataPolicy` on the terminal configuration, separate from `metadata()` (what the source contained) and from pixel analysis:

```swift
try image.jpeg()                                  // the default policy
try image.jpeg().metadataPolicy(.preserveAll)
try image.webp().metadataPolicy(.removeAll)
try image.png().metadataPolicy(MetadataPolicy(icc: .remove, density: .remove))
```

The **default** is privacy-minimising but rendering-safe: EXIF, XMP, IPTC, and comments are removed, while the **ICC profile, orientation, and density** are kept, because they affect how an image displays. (Earlier versions stripped everything, including the profile.) `.preserveAll` keeps everything the format can carry; `.removeAll` removes everything, including the profile, orientation tag, and density, and leaves the pixels untouched, so an image that relied on one of them can display differently. Each family (`exif`, `icc`, `xmp`, `iptc`, `other`, `orientation`, `density`) can be set on its own. The policy maps to libvips' native `keep` flags and is applied identically to `data()` and `write(to:)`.

- **Orientation** is not privacy metadata. `.remove` deletes the tag without rotating pixels; `autoOrient()` is the operation that applies it. EXIF holds the orientation tag, so removing EXIF while keeping orientation leaves a minimal EXIF block with the orientation and the technical entries libvips writes itself (pixel dimensions, resolution, versions), but none of the descriptive or location fields. If EXIF is kept in full, removing the orientation writes the neutral value "up".
- **Density.** Formats always record some resolution, so `.remove` stops the source's from being carried over and the encoder writes its own default.
- **ICC** retention is not a colour conversion: no profile is applied, attached, or changed.

What each format can carry (a family a format cannot carry is simply absent from its output):

| | EXIF | XMP | IPTC | ICC | orientation | density |
|---|---|---|---|---|---|---|
| JPEG | yes | yes | yes | yes | EXIF tag | yes |
| PNG | yes | yes | no | yes | EXIF tag | yes |
| WebP | yes | yes | no | yes | EXIF tag | no |
| AVIF | yes | yes | no | yes | container rotation | no |

AVIF is the exception for orientation. The format stores it as a rotation of the image container rather than as a tag, and a reader applies that rotation and reports no tag, so the decoded side lengths are the rotated ones. Whether libvips writes that rotation depends on the build: with libvips 8.18 it does, while on the 8.16 baseline (libheif 1.12) the orientation survives only as an EXIF tag, which AVIF viewers ignore. If you encode AVIF for such a build, call `autoOrient()` first so the pixels are upright.

### Source metadata

```swift
let metadata = try await Hokusai(url: photoURL).metadata()

metadata.format             // .jpeg, .avif, ... or nil when it cannot be identified
metadata.orientedSize       // the displayed size after EXIF orientation
metadata.pixel.interpretation // .sRGB, .cmyk, ... (not colour management)
metadata.sourceByteSize     // exact for Data, the file size for a file
```

`metadata()` has one meaning: **what the root source reported when it was opened.** It never describes the transformed pipeline, so `image.metadata()` and `image.resize(width: 400).metadata()` are equal, and a composite pipeline reports only its base source (call `metadata()` on an overlay's own value to inspect it). What a pipeline produces is described by `OutputInfo`. It is `async` because it opens the source off Swift's cooperative executor on Hokusai's evaluation scheduler; it reads only the header, so a truncated file with an intact header inspects successfully even though decoding its pixels would fail. `InputOptions` apply: the selected `page`, the input limits, and the access mode.

- **Dimensions** are the stored size of the selected page. EXIF orientation is a separate typed `orientation` (values 1...8, `nil` when absent or invalid) and `orientedSize` swaps width and height only for quarter-turn orientations.
- **Pixel model** (`pixel`): channels, alpha, a curated interpretation, sample format, bits per sample, and, for PNG, whether it is palette-based. An interpretation such as `.sRGB` says how the stored values are read; it does not mean an embedded ICC profile was applied.
- **Pages versus animation.** `pages.count > 1` means multi-page. `animation` (loop count and per-frame delays) exists only when the source carries frame delays, so a multi-page TIFF is not reported as animated.
- **Format** comes from the loader libvips used, not from a file name. AVIF and HEIC share one loader and are told apart by their HEIF compression. Loaders Hokusai does not name (for example JPEG XL) give `nil`.
- **Density** is one value in DPI, plus the source's preferred unit when it records one. libvips reports 1 pixel/mm for a file that recorded no resolution; that default is treated as "none" rather than as 25.4 DPI.
- **Embedded blocks** (`exif`, `iccProfile`, `xmp`, `iptc`) are owned raw `Data`. The IPTC block is the Photoshop image-resource block that carries the IPTC records, exactly as libvips exposes it. `xmpString` decodes XMP only when it is valid UTF-8.

### Output

One encoder configuration means the same thing wherever it is written: `data()` and `write(to:)` apply identical codec options, so `png(progressive: true)`, `jpeg(progressive: true)`, `webp(lossless: true)` and `avif(...)` produce the same bytes in memory and on disk. `.avif()` always encodes AV1, never the HEVC that libvips picks by default, and `OutputInfo.format` names the format that was actually encoded.

- `data()` needs an explicit encoder (`.jpeg()`, `.png()`, `.webp()`, `.avif()`, `.pdf()`), because a pipeline can originate from several sources and "same as the input" has no meaning.
- `write(to:)` infers the encoder from the file extension only when you did not select one. An explicit encoder always wins, so choose a matching extension yourself: `.png().write(to: "a.jpg")` writes PNG data.
- Raster formats are encoded straight into the memory buffer or file; nothing is staged as a second copy. PDF is the exception for now and is built in memory first.
- The file is created when the first bytes are written, so a pipeline that fails before producing output never touches the destination. If a write fails after output began, Hokusai removes the regular file it was writing instead of leaving a partial image, which also means an existing file at that path may be replaced or removed. A destination that cannot be opened or written (missing folder, permissions, full disk) throws `HokusaiError.io` with a `.write` operation and the system's reason.

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
let info = try await Hokusai(url: URL(fileURLWithPath: "photo.jpg"))
    .resize(width: 1240)
    .pdf(
        pageSize: .a4(),
        margins: .all(36),
        background: .white,
        metadata: PDFDocumentMetadata(title: "Site photo")
    )
    .write(to: URL(fileURLWithPath: "report.pdf"))

info.pdf?.pageWidth   // 595.276 points; info.width/height are the embedded pixels
```

`.pdf()` is a **raster-document terminal**: the evaluated pixels are embedded as an image on a page by Cairo. Text drawn into the pipeline has already become pixels, so it is not selectable, and an input PDF that is rasterised and written again loses its vector content, fonts, links, and structure. Vector documents are a separate surface, tracked in [#13](https://github.com/ivantokar/hokusai/issues/13).

- **Page size** says how big the page is, in points: `.image(dpi:)` (the raster at that resolution plus margins), `.a4(_:)`, `.letter(_:)` with a portrait or landscape orientation, or `.points(width:height:)`. Fixed sizes carry no DPI, because there is nothing for a resolution to change.
- **Layout.** The raster is scaled uniformly to fit inside the margins and placed by `anchor` (centred by default).
- **Resolution.** Hokusai never resamples because a page has a physical size. If you want a bound, `maxEffectiveDPI` downsamples a raster that would exceed it on the page before it is embedded.
- **Transparency.** With no `background`, transparent pixels stay transparent in the PDF. A `background` colour paints the page behind the image; use `.white` for print.
- **Colour.** Pixels are rendered as 8-bit sRGB. An embedded ICC profile is neither applied nor embedded.
- **Document properties** are written only if you set them (title, author, subject, keywords, creator, dates). Nothing is copied from the source's EXIF, XMP, or IPTC. Without a `creationDate` Cairo records the current time, so set one for reproducible bytes.
- **Output.** `data()` and `write(to:)` use the same writer. A file is written directly as Cairo produces bytes, never built as `Data` first, and a failed or cancelled write removes the partial file. The raster is converted once into a single buffer, so peak memory is one full-size raster lower than before (about 184 MiB less for an 8000 × 6000 RGBA image).

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

`hokusai thumbnail` is `autoOrient` and `resize` on the same public pipeline as the library. JPEG sources are shrunk by the decoder when the pipeline allows it (see `resize` in the changelog); nothing about the command line changes.

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
- [x] [First-class pipeline thumbnails with shrink-on-load](https://github.com/ivantokar/hokusai/issues/20).
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
