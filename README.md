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

# Debian 13 / Ubuntu 25.10+ (distro libvips 8.16+)
sudo apt update
sudo apt install libvips-dev libcairo2-dev pkg-config
```

Ubuntu 24.04 LTS (libvips 8.15) and Debian 12 ship libvips older than 8.16, so
`apt install libvips-dev` is not enough there: build libvips from a
[release tarball](https://github.com/libvips/libvips/releases) (see
`.github/scripts/install-libvips.sh` for the configuration CI uses).

What CI proves on every pull request:

| Job | Swift | libvips | Cairo | Purpose |
| --- | --- | --- | --- | --- |
| Linux baseline | 6.0 | 8.16.1 | 1.16 | The minimum contract builds and passes |
| Linux current | 6.4 | 8.18.7 | current | Newest toolchain and native stack, with HEIF/AVIF, JPEG XL, palette PNG, PDF and SVG input, and text |
| macOS current | 6.4 | Homebrew | Homebrew | macOS with the same suite |

Each job prints the versions it used and fails if they are below the baseline,
and the current jobs list the capabilities they must have, so a broken native
install fails instead of silently skipping optional tests. libvips 8.17 and
newer add capabilities (for example the Magic Kernel resize kernels) that
Hokusai reports instead of assuming. Hokusai links libvips and Cairo only;
codecs, Pango and fontconfig come with whatever libvips build you install.

Build-dependent capabilities depend on how libvips was compiled, not on
Hokusai's package dependencies: HEIF/AVIF, JPEG XL, JPEG 2000, PDF input, SVG,
Pango text rendering, and other optional codecs. Run `hokusai info` to inspect
the runtime you actually installed.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/ivantokar/hokusai.git", from: "2.0.0")
]
```

Add `Hokusai` to your target dependencies. The optional product `HokusaiNIO` bridges SwiftNIO `ByteBuffer`.

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

One encoder configuration means the same thing wherever it is written: `data()` and `write(to:)` apply identical codec options, so `png(interlaced: true)`, `jpeg(progressive: true)`, `webp(lossless: true)` and `avif(...)` produce the same bytes in memory and on disk. `.avif()` always encodes AV1, never the HEVC that libvips picks by default, and `OutputInfo.format` names the format that was actually encoded.

- `data()` needs an explicit encoder (`.jpeg()`, `.png()`, `.webp()`, `.avif()`, `.pdf()`), because a pipeline can originate from several sources and "same as the input" has no meaning.
- `write(to:)` infers the encoder from the file extension only when you did not select one. An explicit encoder always wins, so choose a matching extension yourself: `.png().write(to: "a.jpg")` writes PNG data.
- Raster formats are encoded straight into the memory buffer or file; nothing is staged as a second copy. PDF is written directly to a file as Cairo produces it; `data()` collects the same writer's bytes (see PDF output). TIFF is the exception that must be encoded in memory first when it is streamed.
- The file is written through a temporary file in the same directory (`.name.hokusai-…`) and renamed over the destination only when the write finished, so a write that fails or is cancelled at any moment leaves an existing file exactly as it was and leaves no partial image, and a reader never sees half a file. The temporary file is created when the first bytes are written, so a pipeline that fails before producing output never touches the destination. A replaced file keeps its permissions; a symbolic link stays a link and its target is replaced; a hard link to the old file is not followed (the other name keeps the old content). A destination that is not a regular file, such as a device or a pipe, and a file in a directory you cannot create files in, are written in place as before. A destination that is a file the pipeline reads, including through a symbolic link or a hard link, is refused with `HokusaiError.invalidOption` (`output URL`) before anything is written, and the file is left as it was; write to a different file and replace the original yourself. A destination that cannot be opened or written (missing folder, permissions, full disk) throws `HokusaiError.io` with a `.write` operation and the system's reason.

### Large uploads

A server that receives an image as a stream of chunks does not have to hold it in memory to decode it:

```swift
let image = try await Hokusai(spooling: request.body, options: .init(limits: .init(maxBytes: 200_000_000)))
```

(`request.body` is a sequence of `ByteBuffer`; the `Data` form is `Hokusai(spooling:)` in the core module, the `ByteBuffer` form comes with `HokusaiNIO`.)

- The upload stays in memory while it is within `memoryLimit` (1 MiB by default) and moves to a temporary file when it grows past it, so the encoded upload never takes more than `memoryLimit` plus one chunk of memory. libvips reads the image from the file with random access; the decode does not need the body as one buffer. The memory libvips uses to decode and transform the image is a separate matter (`InputOptions.access`, `InputLimits.maxPixels`).
- `InputLimits.maxBytes` applies while the body is read: the chunk that crosses it throws `HokusaiError.resource` (`encodedBytes`) and the rest of the body is never requested.
- The pipeline owns the file. It is removed when the last copy of the pipeline, and any evaluation running on it, is released; a failed or cancelled read removes it at once. A process that is killed first leaves its file: files are named `hokusai-upload-…`, are readable by their owner only, and sit in `spoolDirectory` (the system temporary directory by default), so a server can sweep that directory at startup.

### Raw pixels

Pixels that already live in memory (a renderer, a camera buffer, a computer-vision step, a binary protocol) go in and out without being encoded:

```swift
let frame = try Hokusai(raw: pixels, width: 640, height: 480, format: .rgba8)
let small = try await frame.resize(width: 320).raw(.rgb8, background: .white)
// small.data, small.width, small.height, small.format, small.rowStride
```

- A `RawPixelFormat` is one of `gray8`, `grayAlpha8`, `rgb8`, `rgba8`, `gray16`, `grayAlpha16`, `rgb16`, `rgba16`: interleaved unsigned samples, colour first and alpha last, no padding between pixels, rows top to bottom. 16-bit samples use the machine's byte order (little-endian on every supported platform). Colour is sRGB; no ICC profile is applied.
- Input is validated before any native call: the byte count must match `width × height × bytesPerPixel` (or the row stride you give, `rowStride`, where the padding after the last row may be missing), dimensions and sizes are checked for overflow, and `InputLimits` apply. A mismatch throws `HokusaiError.invalidInput`, a bad dimension or stride `invalidOption`, a limit `resource`. The bytes are retained copy-on-write and copied into native storage at evaluation, so nothing borrows your memory across an `await`.
- `premultiplied: true` says the input colour is already multiplied by alpha; it is divided out on load so every operation sees straight alpha, as for an encoded source.
- `raw(_:premultiplied:background:)` is a terminal like `data()`. It returns a `RawImage` that carries the dimensions, format, row stride (always tight) and alpha convention, so the bytes cannot be misread, and `Hokusai(raw: rawImage)` feeds it back in. Converting between layouts follows libvips: grey is repeated for an RGB format, colour is reduced to luminance for a grey format, 8 and 16 bits are rescaled (white stays white), alpha is added opaque, or composited over `background` when the format has none. No metadata is kept, and an encoder must not be selected on the pipeline.

### Streaming output

```swift
let info = try await image
    .webp(quality: 82)
    .writeChunks(chunkSize: 64 * 1024) { chunk in      // chunk: Data
        try await response.write(chunk)
    }
```

`writeChunks` hands the encoded bytes to an async closure as they are produced, so a response can start before the image is fully encoded and a slow client slows encoding down instead of growing memory. It needs an explicit encoder, applies the same codec options and metadata policy as `data()` and `write(to:)`, and returns the final `OutputInfo` (its `byteCount` is the total streamed).

- Chunks are owned `Data` of `chunkSize` bytes (the last may be smaller, none are empty). The next chunk is not produced until your closure returns for the previous one, and at most `chunkSize × 4` bytes of *encoded output* are held in the hand-off at any time (TIFF excepted, below). That bounds the queue between the encoder and your closure, not the memory libvips and the codecs use to decode, transform and encode the image, which depends on its size and on `maxConcurrentEvaluations`.
- If your closure throws, encoding stops and your error is thrown. Cancelling the calling task stops encoding and throws `CancellationError`. Either way, and if encoding fails after output began, the consumer has already received a partial stream and must discard it.
- A failure before any output (a missing file, a limit, an unsupported encoder) never calls your closure.
- TIFF is the one format that cannot be written forward-only, so it is encoded in memory first and then streamed in chunks.
- The core has no SwiftNIO dependency. `HokusaiNIO` adds `writeByteBuffers(allocator:chunkSize:_:)`, the same stream with each chunk as a `ByteBuffer` from your allocator, for NIO-based writers such as Vapor 4 and Hummingbird.

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
- **Decoder failure level** (`failOn`): `.none` decodes whatever it can; `.truncated` fails on truncated files; `.error` also fails on decoder errors; `.warning` (the default, as in Sharp) also fails on decoder warnings, so it rejects slightly malformed but viewable images. Failures are `HokusaiError.decode`. Choose the level that matches how strict your application must be. With `.none` a damaged file is decoded with the missing data padded, so a tiny file whose header claims a very large size still costs the memory and time of that size (inside `limits.maxPixels`); a service that uses `.none` should lower `maxPixels` too.
- **Access** (`access`): `.random` (default) allows any pixel order. `.sequential` streams top to bottom with lower peak memory for single-pass pipelines; operations that read out of order may fail with a decode error. Measure before using it: for heavily downscaled JPEGs it was slower in our benchmarks.
- **Pages** (`page`): selects exactly one zero-based page (TIFF, PDF, GIF, WebP, ...). Without it you get the first page. A page beyond the file's page count is an `invalidOption`; selecting a page other than 0 in a single-page format is `unsupported`. Page ranges, all-page loading, and animation are not supported; see [Multi-page and animation](#multi-page-and-animation).
- **Limits** (`limits`): `maxBytes` (default 512 MiB) is checked before `Data` is copied and against a file's size; `maxPixels` (default 268,402,689, i.e. 16383 × 16383) and `maxChannels` (default 8) are checked from the header before any pixels are decoded. Exceeding one throws `HokusaiError.resource`. Tighten them to your upload policy; native codec safety limits always remain in force. **These limits judge the source, not the result.** The size of what a pipeline produces is bounded by `RuntimeConfiguration.maxOutputPixels` (default 1,073,741,824, i.e. 2^30 pixels; `nil` removes the bound): every image the pipeline creates, final or intermediate, is checked as the pipeline is lowered, before any pixel is computed, and one over the limit fails with `HokusaiError.resource` (kind `.outputPixels`). The default only refuses sizes no real canvas has, so `resize(width: 10_000_000)` of a small image fails at once instead of occupying a slot. A service should set it to its own policy: `try Hokusai.configure(.init(maxOutputPixels: 100_000_000))`.
- **Freshness** (`revalidate`): libvips caches recent file opens, so a file replaced at the same path may be served from cache. `revalidate: true` bypasses the cache for that open. It has no effect on `Data`, and Hokusai keeps no cache of its own.

## Transformations

```swift
let base = try Hokusai(url: URL(fileURLWithPath: "photo.jpg"))
let logo = try Hokusai(url: URL(fileURLWithPath: "logo.png"))

let label = TextStyle(
    font: "sans Bold", fontSize: 48, color: .white,
    stroke: TextStroke(color: Color(red: 0, green: 0, blue: 0), width: 2))

let image = try base
    .resize(width: 1200, height: 800, fit: .cover)
    .composite([CompositeLayer(logo, placement: .gravity(.northWest, offsetX: 32, offsetY: 32), opacity: 0.8)])
    .drawText("Hello, Hokusai", placement: .gravity(.southWest, offsetX: 80, offsetY: 40), style: label)
    .flatten(background: .white)

// Text is an ordinary pipeline too: transform it, or encode it on its own.
let badge = try Hokusai.text("SALE", layout: .fit(width: 300, height: 120)).png().data()
```

Core operations include resize, extract, rotate, auto-orient, composite, blur, sharpen, trim (with background, line-art and margin controls), smart crop, tint, flatten/remove alpha, metadata inspection, and typed JPEG/PNG/WebP/AVIF output.

### Advanced filters

Typed operations beyond the common effects. Each keeps alpha deliberately, keeps the image's sample type (8 or 16 bits), and rejects bad parameters before any native work:

```swift
let kernel = try ConvolutionKernel(width: 3, height: 3, values: [0, -1, 0, -1, 5, -1, 0, -1, 0])
let result = try image
    .convolve(kernel)            // custom kernel; coefficients, scale and offset are validated
    .linear(multiply: 1.1, add: -8)   // contrast and brightness on the colour channels
    .recombine(.sepia)           // 3×3 colour matrix; .luminance, .swapRedBlue, or your own nine numbers
    .erode().dilate()            // morphology on a mask: removes specks
    .edges(.canny(sigma: 1.4))   // edge strength of the luminance: .sobel, .scharr, .prewitt, .canny
```

- **Channels** are named, not numbered: `extractChannel(.red / .green / .blue / .alpha / .luminance)` reads the image as sRGB first (a grey, CMYK or other source is converted) and returns a grey image; asking an opaque image for `.alpha` throws. `withAlpha(from:)` uses another pipeline's luminance as this image's alpha (same size required; an existing alpha is replaced), which with `extractChannel` moves alpha between images.
- `dilate` and `erode` take the maximum or minimum of a square `2 × radius + 1` window on each channel; on a black-and-white mask (`threshold`) they widen or narrow the white. `edges` returns one channel, the image's sample type and its alpha; it measures change in luminance and is not object detection.
- Not yet: custom morphology masks, boolean band operations, and the specialised operators (histogram matching, frequency-domain filters, Hough transforms). They are tracked as separate issues when a concrete use appears.

## Multi-page and animation

Hokusai reads **one page at a time** and writes **one page at a time**. This is the contract for 2.0:

- **Input.** `InputOptions.page` selects one zero-based page or frame of a TIFF, GIF, animated WebP, PDF (when libvips has poppler), or similar source. Without it you get the first. Pixel limits (`maxPixels`) apply to that selected page, so a hundred-frame GIF costs one frame of pixels. There is no all-pages or range option; asking for one is not expressible, and a page beyond the end fails with `invalidOption("page")`.
- **Metadata.** `pages.count` and `pages.height` describe document structure and are never taken to mean animation. `animation` (loop count, per-frame delays) exists only when the source carries frame timing, and `isAnimated` is derived from it, so a three-page TIFF is multi-page but not animated. `metadata()` always describes the source header, whichever page you selected.
- **Output.** Every encoder writes a single image. An animated GIF or WebP that is transformed and encoded again produces its selected frame only (not an animation), and `Hokusai(data: output.data).metadata().pages.count` is 1. `pdf()` writes one raster page.

**Decision: animated and multi-page output is no-go for the 2.0 core.** Processing every frame multiplies the cost of a single image: libvips holds the frames of a multi-page image stacked in one tall image, so memory is roughly `frames × width × height × bands` bytes (a 100-frame 1000×1000 RGBA GIF is about 400 MB decoded) and each operation runs once per frame. Offering it would need a frame budget alongside `maxPixels`, per-frame handling for every operation (resize, composite, text), and delay and loop encoding. That is a separate, additive feature rather than something the pipeline should do implicitly; it is tracked as follow-up work, and page selection is the supported way to work with individual frames today.

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

`.pdf()` is a **raster-document terminal**: the evaluated pixels are embedded as an image on a page by Cairo. Text drawn into the pipeline has already become pixels, so it is not selectable, and an input PDF that is rasterised and written again loses its vector content, fonts, links, and structure. For selectable text and vector content use the separate `HokusaiPDF` product, described below.

- **Page size** says how big the page is, in points: `.image(dpi:)` (the raster at that resolution plus margins), `.a4(_:)`, `.letter(_:)` with a portrait or landscape orientation, or `.points(width:height:)`. Fixed sizes carry no DPI, because there is nothing for a resolution to change.
- **Layout.** The raster is scaled uniformly to fit inside the margins and placed by `anchor` (centred by default).
- **Resolution.** Hokusai never resamples because a page has a physical size. If you want a bound, `maxEffectiveDPI` downsamples a raster that would exceed it on the page before it is embedded.
- **Transparency.** With no `background`, transparent pixels stay transparent in the PDF. A `background` colour paints the page behind the image; use `.white` for print.
- **Colour.** Pixels are rendered as 8-bit sRGB. An embedded ICC profile is neither applied nor embedded.
- **Document properties** are written only if you set them (title, author, subject, keywords, creator, dates). Nothing is copied from the source's EXIF, XMP, or IPTC. Without a `creationDate` Cairo records the current time, so set one for reproducible bytes.
- **Output.** `data()` and `write(to:)` use the same writer. A file is written as Cairo produces bytes, never built as `Data` first, through the same temporary file as every other format, so a failed or cancelled write leaves an existing file untouched. The raster is converted once into a single buffer, so peak memory is one full-size raster lower than before (about 184 MiB less for an 8000 × 6000 RGBA image).

### Vector PDF documents (`HokusaiPDF`)

A separate product in the same package draws pages directly with Cairo and Pango, so text stays real, selectable and searchable text, and shapes and gradients stay vector. Images are Hokusai pipelines, embedded as rasters. The core does not depend on Pango; only code that imports `HokusaiPDF` needs it (Pango 1.44 or later: `libpango1.0-dev`, or `brew install pango`).

```swift
import Hokusai
import HokusaiPDF

let cover = try VectorPage(size: .a4())
    .background(.linearGradient(from: navy, to: teal))                        // or .color(...), or several stops
    .image(hero.resize(width: 715), frame: VectorRect(x: 40, y: 40, width: 515, height: 200), fit: .cover)
    .text("Quarterly Performance", at: VectorPoint(x: 40, y: 270), width: 515,
          style: VectorTextStyle(family: "sans", size: 30, weight: .bold, color: .white))
    .rectangle(VectorRect(x: 40, y: 330, width: 160, height: 90), fill: .color(navy), cornerRadius: 8)
    .line(from: VectorPoint(x: 40, y: 440), to: VectorPoint(x: 555, y: 440), stroke: VectorStroke(color: .white))

let document = VectorDocument(pages: [cover], metadata: PDFDocumentMetadata(title: "Q3 report"))
try await document.write(to: URL(fileURLWithPath: "report.pdf"))     // or: let pdf = try await document.data()
```

- **Coordinates** are PDF points (1/72 inch), origin at the top-left, y growing downwards. Page sizes: `.a4()`, `.letter()` (portrait or landscape) or `.points(width:height:)` (1 to 14400).
- **Items** are drawn in the order they are added: `background`, `rectangle` (fill, stroke, corner radius), `line`, `image` (`.contain`, `.cover`, `.fill`, opacity), and `text`. A page is an immutable value, and each item is validated when it is added.
- **Text** is plain or Pango markup (`TextContent`), with a typed `VectorTextStyle`: font family, size, weight, italic, colour, alignment (including justified), wrapping, and line spacing. A width wraps lines; without one only line breaks do. The font is resolved by fontconfig (CoreText-backed on macOS) and embedded as a subset with a character map, which is what makes the text searchable. A family that is not installed falls back to the system default.
- **Images** are evaluated when the document is written and embedded at their own resolution; resize them to about the pixel size the frame needs (100 to 150 dpi for screens) to keep the file small. Alpha is kept.
- **Output** is `data()` (with the page count and byte size) or `write(to:)`, which replaces an existing file atomically. Invalid markup, a failing image pipeline, or a Cairo failure throw `HokusaiError`; cancelling the task throws `CancellationError`.
- **Not in the first version:** embedding font files, tables and columns, links and bookmarks, rotated text, and streaming the PDF while it is built.

## Runtime

libvips is process-scoped: Hokusai initializes it at most once and it stays available until the process exits. There is no teardown API; the operating system reclaims native resources at exit. Loading a pipeline initializes the runtime automatically; call `Hokusai.initialize()` at startup only to surface initialization failures early.

### Configuration

Runtime settings are process-wide and belong in application startup:

```swift
try Hokusai.configure(.init(
    maxConcurrentEvaluations: .fixed(4),  // pipelines evaluated at once
    maxQueuedEvaluations: 64,             // waiting pipelines before .resource
    vipsConcurrency: .fixed(2),           // libvips threads per image computation
    blockUntrustedOperations: true        // refuse PDF, SVG, ImageMagick and OpenSlide input
))
```

`configure(_:)` may be called once. Configuration freezes at the first `initialize()`, `capabilities()`, or `data()`/`write(to:)`; building pipelines does not freeze it. Later calls throw.

The two concurrency settings are different resources. `maxConcurrentEvaluations` limits how many whole pipelines Hokusai runs at once, which bounds memory and latency; extra evaluations wait in FIFO order as suspended tasks. `vipsConcurrency` sets how many libvips worker threads one image computation may use. With both `.automatic`, Hokusai admits one evaluation per active processor and libvips uses its own default. These defaults are provisional: no benchmark has yet shown them to be best for any workload, and `hokusai benchmark run` sweeps both dimensions so you can measure your own. Set both explicitly for a production service. `maxQueuedEvaluations` (unbounded by default) rejects new work with `HokusaiError.resource` (kind `.queuedEvaluations`) instead of retaining more source bytes in memory.

**Untrusted input.** `blockUntrustedOperations` turns on libvips' own switch for loaders it marks untrusted (poppler PDF, SVG, ImageMagick, OpenSlide). Turn it on for services that decode uploads from strangers; a source in a blocked format then fails as `decode`. JPEG, PNG, WebP, GIF, TIFF and HEIF are not affected, and neither is `pdf()` output, which is Cairo. libvips reads `VIPS_BLOCK_UNTRUSTED` too, so setting that environment variable has the same effect.

**Cache controls are deliberately not exposed.** libvips' operation cache (`vips_cache_set_max`, `set_max_mem`) can help or hurt depending on the workload, and Hokusai has no benchmark that justifies a typed default or a safe range. Leave libvips' defaults, or set `VIPS_CACHE_MAX`-style environment variables yourself, until that evidence exists.

### Capabilities and status

```swift
let capabilities = try Hokusai.capabilities()
guard capabilities.canEncode(.avif) else { /* offer WebP instead */ }

let status = Hokusai.runtimeStatus
print(status.queuedEvaluations, status.activeEvaluations)
```

Codec availability depends on how libvips was built, not on Hokusai's package dependencies. Reading and writing AVIF are reported separately: writing is verified by encoding a tiny image, reading by decoding a small embedded AVIF, because a build can have an AV1 decoder without an AV1 encoder and the other way round. PDF input (libvips `pdfload`) and PDF output (Cairo) are reported separately, and `blockedInputFormats` lists formats the build can decode but `blockUntrustedOperations` has switched off, so "absent" and "blocked" are not confused. Font-file loading (`TextStyle.fontFile`) is not reported because libvips only warns when it cannot load one, so it cannot be probed reliably. `hokusai info` prints the same report.

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

`hokusai run` writes a pipeline the way the library does: an input, steps named after the API methods in the order they apply, and an output. The image is decoded once and encoded once, however many steps there are.

```bash
# autoOrient -> resize -> blur -> webp, as one evaluation
hokusai run photo.jpg auto-orient resize --width 1200 --height 630 --fit cover blur --sigma 1.5 webp --quality 82 -o social.webp --json

# generated text is a source, like Hokusai.text(...)
hokusai run --text "Hokusai" --font-size 48 png -o title.png

# standard input and output
cat photo.jpg | hokusai run - resize --width 400 jpeg -o - > small.jpg

hokusai run photo.jpg resize --help        # the options of one step
hokusai run --help                         # every step
hokusai info
hokusai inspect --input photo.jpg --json
hokusai benchmark run --input photo.jpg --workloads blur-webp --evaluations 1,2,4 --vips-concurrency 1,auto --json-output result.json
hokusai benchmark compare base.json result.json
```

- **Steps are the API.** One step per public method: `auto-orient`, `resize`, `rotate`, `flip`, `flop`, `extract`, `extend`, `affine`, `trim`, `smart-crop`, `blur`, `sharpen`, `grayscale`, `tint`, `normalize`, `clahe`, `gamma`, `negate`, `median`, `threshold`, `modulate`, `convert-to`, `ensure-alpha`, `flatten`, `remove-alpha`, `composite`, `draw-text`, the advanced filters `convolve`, `linear`, `recombine`, `dilate`, `erode`, `edges`, `extract-channel`, `with-alpha`, the encoders `jpeg`, `png`, `webp`, `avif`, `heif`, `tiff`, `gif`, `pdf`, and `metadata-policy`. A step takes the options of its method, with the method's defaults, so `resize` is `cover` and text is 24 pt black exactly as in Swift. An option belongs to the steps that have it: `png --quality 10` and `resize --palette` are errors, never accepted and ignored. A value that starts with a dash is written `--hue=-30`.
- **Input.** A path, `-` for standard input, or `--text` / `--markup`. `--page`, `--access`, `--fail-on`, `--max-bytes`, `--max-pixels`, `--max-channels` and `--revalidate` are the fields of `InputOptions` and `InputLimits`.
- **Output.** `-o <path>` writes a file; when no encoder step is given its extension chooses the encoder, as `write(to:)` does. `-o -` writes to standard output and needs an encoder step. `--json` prints the result (`OutputInfo`: format, size, byte count, MIME type) as one JSON object, on standard error when standard output carries the image. Not covered by a step: TIFF and PDF details beyond the options listed in `--help`, and layers built from pipelines rather than files.
- **The older commands** `resize`, `thumbnail`, `convert`, `rotate`, `crop` and `text` still work, print a deprecation notice on standard error and will be removed in the next major version. Their defaults now match the library (`resize` is `cover`, text is 24 pt black), and `convert` refuses a flag its format has no use for (`--quality` to PNG) instead of ignoring it. `convert` and `text` named other things than the methods with those names; `hokusai run` has no such overlap (`convert-to` changes the colour space, an encoder step or the output extension chooses the format, and `draw-text` draws).

The command line is a client of the public API and adds no image processing of its own. Each command parses its arguments, builds an ordinary Hokusai pipeline, and reports the result. The code lives in `HokusaiCommandLine`, which depends only on the public `Hokusai` module; the `hokusai` executable is just its entry point.

- **Strict arguments.** An unknown `--fit`, `--kernel`, `--align` or `--crop` word, or a colour (`r,g,b[,a]`, each 0...255) that is malformed, not finite or out of range, is an error, never a default or a clamp. Numeric ranges such as quality and dimensions are validated by Hokusai itself, so the CLI and the library cannot disagree.
- **`convert`** writes the public encoder set (JPEG, PNG, WebP, AVIF, HEIF, TIFF, GIF, PDF). An encoder the linked libvips lacks is reported as unsupported; `hokusai info` lists what is available. SVG is input only. `--format` that contradicts the output extension is refused rather than written under a misleading name.
- **Metadata.** Without a flag, Hokusai's default policy applies unchanged. `--strip-metadata` is the deliberate remove-everything policy.
- **`thumbnail`** is `autoOrient` (unless `--no-rotate`) followed by `resize`, with the library's semantics. JPEG sources may be shrunk by the decoder when the pipeline allows it (see `resize` in the changelog); nothing about the command line changes.
- **`inspect`** reports the source file's metadata, and only notes that EXIF, ICC, XMP and IPTC blocks exist.
- **`benchmark run`** sweeps the two independent concurrency dimensions, `--evaluations` (how many evaluations run at once) and `--vips-concurrency` (threads inside each), and launches a **fresh worker process per cell**, so every measurement has its own frozen runtime configuration and no cache or runtime state leaks between cells. Each concurrent request reads its own copy of the input, so libvips' operation cache cannot make requests look cheaper than they are. `--profile quick` is a local smoke run; `--profile stable` takes enough samples for tail latency, and a percentile the sample count cannot support is reported as `n/a` rather than invented. `--json-output` writes a versioned result (commit, Swift, OS, CPU, libvips and Cairo versions, runtime settings, input SHA-256, raw samples, throughput, encoded bytes, active/queued high-water, peak RSS). Workloads: `thumbnail-jpeg`, `cover-webp`, `blur-webp`, `resize-png`, `pdf-a4`.
- **`benchmark compare`** matches cells of two results and flags a change in median latency, and in the worker's peak resident memory, only when it exceeds both a relative and an absolute threshold (`--relative-threshold`, `--absolute-threshold-ms`, `--memory-relative-threshold`, `--memory-absolute-threshold-mib`). It is advisory, always exits zero, and warns when the two runs came from different native stacks. Absolute milliseconds are not portable; compare base and candidate on the same machine.
- **Failures** are one line built from the error's case. `--verbose` adds the native diagnostic when there is one.

## Roadmap

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
- [x] [Complete page, decoder-failure, and upload-safety input controls](https://github.com/ivantokar/hokusai/issues/21).
- [ ] [Typed raw-pixel input and output](https://github.com/ivantokar/hokusai/issues/22).

### Output, metadata, and composition

- [x] [Capability-aware TIFF, GIF, and HEIF output](https://github.com/ivantokar/hokusai/issues/23).
- [x] [Statistics and granular EXIF, ICC, XMP, orientation, and density controls](https://github.com/ivantokar/hokusai/issues/24).
- [x] [Gravity placement and a broader typed blend-mode set](https://github.com/ivantokar/hokusai/issues/25).
- [ ] [A staged set of advanced transforms](https://github.com/ivantokar/hokusai/issues/26), beginning with common server-side operations rather than a generic native wrapper.
- [x] [A documented multi-page and animation contract](https://github.com/ivantokar/hokusai/issues/27).

### Server operation and migration

- [x] Idempotent, process-safe, one-way libvips initialization.
- [x] Concurrent pipeline evaluation and copied buffer-input ownership.
- [x] [Runtime format capabilities, queue observability, and safe process-level configuration](https://github.com/ivantokar/hokusai/issues/28).
- [x] [A clean 1.0-first public API boundary and semver-safe legacy retirement plan](https://github.com/ivantokar/hokusai/issues/29).
- [x] [Correct the CLI thumbnail documentation to match its implementation](https://github.com/ivantokar/hokusai/issues/30).

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
- [Contributing](CONTRIBUTING.md)
