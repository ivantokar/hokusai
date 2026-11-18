<p align="center">
<img src="./hokusai-logo-v4.png" alt="Hokusai — Swift image processing library" width="500">
</p>

# Hokusai

## High-performance Swift image processing

Hokusai is a Swift image-processing library powered by [libvips](https://www.libvips.org/) for server-side applications. It provides a clear, immutable pipeline API: build a recipe synchronously, then evaluate it with an asynchronous output terminal.

libvips processes images on demand, using small regions of pixel data at a time and available CPU cores efficiently. Hokusai exposes that capability through Swift without spawning child processes.

**Documentation: <https://ivantokar.com/oss/hokusai/>** (English) · [Українською](https://ivantokar.com/oss/hokusai/uk/). Guides for every operation, recipes, integrations and the CLI reference; every code sample and image there is produced by running the library.

- [Packages](#packages)
- [Requirements](#requirements) · [Installation](#installation) · [Quick start](#quick-start)
- [What you can do](#what-you-can-do)
- [Behaviour you can rely on](#behaviour-you-can-rely-on)
- [Command line](#command-line) · [Documentation map](#documentation-map)
- [Related projects](#related-projects) · [Contributing](#contributing) · [License](#license)

## Packages

| Package | What it is for |
| --- | --- |
| **Hokusai** (this repository) | The core library, with the optional `HokusaiNIO` (SwiftNIO buffers) and `HokusaiPDF` (vector PDF documents) products and the `hokusai` command-line tool |
| [**Hokusai Vapor**](https://github.com/ivantokar/hokusai-vapor) | Adapter for [Vapor](https://vapor.codes): read an upload into a pipeline and stream the result as a response |
| [**Hokusai Hummingbird**](https://github.com/ivantokar/hokusai-hummingbird) | The same for [Hummingbird](https://github.com/hummingbird-project/hummingbird) |
| [**Hokusai examples**](https://github.com/ivantokar/hokusai-examples) | A web playground served by Vapor and by Hummingbird, and a native macOS playground |
| [**Hokusai documentation**](https://github.com/ivantokar/hokusai-docs) | The source of the documentation site |

The adapters are thin: they connect a web framework to the core library and change nothing about how images are processed. Using a plain Swift app, a script or the command line, you only need the core library.

## Requirements

- Swift 6.0+ (tested with Swift 6.0 and 6.4)
- macOS 13+ or Linux
- libvips 8.16+ (older versions are rejected at compile time)
- Cairo 1.16+ with PDF surface support
- `pkg-config`

```bash
# macOS
brew install vips cairo pkg-config

# Debian 13 / Ubuntu 25.10+ (distro libvips 8.16+)
sudo apt update
sudo apt install libvips-dev libcairo2-dev pkg-config
```

Ubuntu 24.04 LTS (libvips 8.15) and Debian 12 ship a libvips older than 8.16, so `apt install libvips-dev` is not enough there: build libvips from a [release tarball](https://github.com/libvips/libvips/releases) (see `.github/scripts/install-libvips.sh` for the configuration CI uses). The [installation guide](https://ivantokar.com/oss/hokusai/guide/installation/) covers every platform, including Docker.

Hokusai links libvips and Cairo only. Codecs, Pango and fontconfig come with whatever libvips build you install, so format support (HEIF/AVIF, JPEG XL, PDF and SVG input, text rendering) depends on how that libvips was compiled. Run `hokusai info` to see what your runtime can do.

What CI proves on every pull request:

| Job | Swift | libvips | Cairo | Purpose |
| --- | --- | --- | --- | --- |
| Linux baseline | 6.0 | 8.16.1 | 1.16 | The minimum contract builds and passes |
| Linux current | 6.4 | 8.18.7 | current | Newest toolchain and native stack, with HEIF/AVIF, JPEG XL, palette PNG, PDF and SVG input, and text |
| macOS current | 6.4 | Homebrew | Homebrew | macOS with the same suite |

Each job prints the versions it used and fails if they are below the baseline, and the current jobs list the capabilities they must have, so a broken native install fails instead of silently skipping optional tests.

## Installation

```swift
dependencies: [
    .package(url: "https://github.com/ivantokar/hokusai.git", from: "2.0.0")
]
```

Add `Hokusai` to your target dependencies. The optional product `HokusaiNIO` bridges SwiftNIO `ByteBuffer`, and `HokusaiPDF` draws vector PDF documents (it is the only product that needs Pango 1.44+: `libpango1.0-dev`, or `brew install pango`).

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

Building a pipeline only records what to do. The source is opened and processed when `data()` or `write(to:)` runs, so invalid image bytes, missing files and pixel-dependent errors are thrown by the terminal, not by `Hokusai(data:)` or the transform call. Option validation (dimensions, quality, colours) still happens immediately. Pipelines are immutable and safe to branch across tasks, so there is no `clone()`.

```swift
let fromData = try Hokusai(data: uploadData)                       // or Hokusai(url:), Hokusai(raw:…), Hokusai.text(…)
let jpeg = try await fromData.jpeg(quality: 85).data()             // encoded bytes
let info = try await fromData.png().write(to: outputURL)           // a file, replaced atomically
let metadata = try await fromData.metadata()                       // what the source reported
```

## What you can do

| Area | Highlights | Guide |
| --- | --- | --- |
| Geometry | resize (`cover`, `contain`, smart crop with `.attention` and `.entropy`), extract, extend, rotate, flip, affine, trim, shrink-on-load thumbnails | [Geometry](https://ivantokar.com/oss/hokusai/geometry/) |
| Colour and effects | blur, sharpen, tint, grayscale, gamma, CLAHE, modulate, convolution, morphology, edge detection, colour matrices | [Effects and colour](https://ivantokar.com/oss/hokusai/effects-color/) |
| Alpha and channels | flatten, remove or ensure alpha, named channel extraction, alpha from another image | [Channels and transparency](https://ivantokar.com/oss/hokusai/channels-transparency/) |
| Text and composition | Pango text with stroke, gravity placement, layered `composite` with blend modes and masks | [Text and composition](https://ivantokar.com/oss/hokusai/text-composition/) |
| Output | JPEG, PNG, WebP, AVIF, HEIF, TIFF, GIF and PDF; `data()`, `write(to:)`, bounded `writeChunks` streaming, raw pixels | [Encoding and output](https://ivantokar.com/oss/hokusai/encoding-output/) |
| Input | `Data`, local files, chunked uploads spooled to disk, raw pixels, generated text; page selection, decode strictness and size limits | [Sources and input](https://ivantokar.com/oss/hokusai/sources-input/) |
| Inspection | typed header metadata, pixel model, density, pages and animation timing | [Inspection](https://ivantokar.com/oss/hokusai/inspection/) |
| PDF | raster-document PDF from any pipeline, and selectable-text vector documents with `HokusaiPDF` | [PDF](https://ivantokar.com/oss/hokusai/pdf/) |

Not every operation is listed here: [find an operation](https://ivantokar.com/oss/hokusai/reference/operations/) lists them all, and the [recipes](https://ivantokar.com/oss/hokusai/recipes/) show them combined (avatars, social cards, watermarks, contact sheets, upload normalisation, PDF reports).

Hokusai borrows the server-side ergonomics of [sharp](https://sharp.pixelplumbing.com/) (clear input, fluent transforms, configured output, useful metadata) and keeps them Swift-native: value semantics, `async`/`await`, typed options instead of option bags, and local inputs rather than remote URL fetching. Animated and multi-page *output*, deep-zoom tiling and unrestricted native-operation dispatch are deliberately not part of the core.

## Behaviour you can rely on

- **A pipeline means what you wrote.** Operations run in the order written. Hokusai may skip provable identities and build a shared source once per evaluation, but it never reorders or fuses your steps. [Evaluation](https://ivantokar.com/oss/hokusai/core-concepts/evaluation/)
- **Safe metadata by default.** Output drops EXIF, XMP, IPTC and comments, and keeps ICC profile, orientation and density, which affect display. A typed `MetadataPolicy` changes that per family. [Metadata](https://ivantokar.com/oss/hokusai/encoding-output/metadata/)
- **One encoder configuration means the same bytes** in `data()`, `write(to:)` and `writeChunks`. Files are written through a temporary file and renamed, so a failed or cancelled write never leaves half an image, and writing over the file a pipeline reads is refused. [Terminals](https://ivantokar.com/oss/hokusai/encoding-output/terminals/)
- **Bounded by design.** Input limits (`maxBytes`, `maxPixels`, `maxChannels`) judge the source, `RuntimeConfiguration.maxOutputPixels` judges every image the pipeline creates, and `writeChunks` holds at most four chunks of encoded output. [Input options](https://ivantokar.com/oss/hokusai/sources-input/input-options/)
- **Cancellation works.** Cancelling the calling task removes a queued evaluation or asks libvips to stop a running one, and the terminal throws `CancellationError`. Evaluations beyond the scheduler's limit wait in FIFO order. [Runtime](https://ivantokar.com/oss/hokusai/runtime-performance/runtime/)
- **Safe for untrusted uploads.** `blockUntrustedOperations` refuses libvips' untrusted loaders (PDF, SVG, ImageMagick, OpenSlide), and `failOn` sets how strict decoding is.
- **Errors you can branch on.** Terminals throw `HokusaiError` (`invalidInput`, `invalidOption`, `unsupported`, `decode`, `transform`, `encode`, `io`, `resource`, `runtime`); match the case, never the message. [Troubleshooting](https://ivantokar.com/oss/hokusai/troubleshooting-migration/troubleshooting/)

Runtime settings are process-wide and belong at startup. `configure(_:)` may be called once, before the first evaluation:

```swift
try Hokusai.configure(.init(
    maxConcurrentEvaluations: .fixed(4),  // pipelines evaluated at once
    maxQueuedEvaluations: 64,             // waiting pipelines before .resource
    vipsConcurrency: .fixed(2),           // libvips threads per image computation
    blockUntrustedOperations: true        // refuse PDF, SVG, ImageMagick and OpenSlide input
))

let capabilities = try Hokusai.capabilities()
guard capabilities.canEncode(.avif) else { /* offer WebP instead */ }
```

The concurrency defaults are provisional; set both explicitly for a production service and measure with `hokusai benchmark run`.

## Command line

`hokusai run` builds the same pipeline from the command line: an input, steps named after the API methods in the order they apply, and an output. The image is decoded once and encoded once.

```bash
# autoOrient -> resize -> blur -> webp, as one evaluation
hokusai run photo.jpg auto-orient resize --width 1200 --height 630 --fit cover blur --sigma 1.5 webp --quality 82 -o social.webp --json

# generated text is a source, like Hokusai.text(...)
hokusai run --text "Hokusai" --font-size 48 png -o title.png

hokusai run photo.jpg resize --help        # the options of one step
hokusai info                               # libvips and Cairo versions, readable and writable formats
hokusai inspect --input photo.jpg --json
hokusai benchmark run --input photo.jpg --workloads blur-webp --evaluations 1,2,4 --vips-concurrency 1,auto --json-output result.json
hokusai benchmark compare base.json result.json
```

The CLI is a client of the public API and adds no image processing of its own. The older commands `resize`, `thumbnail`, `convert`, `rotate`, `crop` and `text` still work, print a deprecation notice and will be removed in the next major version. Full reference: [CLI](https://ivantokar.com/oss/hokusai/reference/cli/).

## Documentation map

| I want to… | Read |
| --- | --- |
| Get a first image out | [Getting started](https://ivantokar.com/oss/hokusai/guide/getting-started/) |
| Find the operation for a task | [Find an operation](https://ivantokar.com/oss/hokusai/reference/operations/) |
| Copy a working solution | [Recipes](https://ivantokar.com/oss/hokusai/recipes/) |
| Handle uploads, raw pixels or page selection | [Sources and input](https://ivantokar.com/oss/hokusai/sources-input/) |
| Choose formats and control metadata | [Encoding and output](https://ivantokar.com/oss/hokusai/encoding-output/) · [Formats and compatibility](https://ivantokar.com/oss/hokusai/reference/formats-and-compatibility/) |
| Build PDFs | [PDF output](https://ivantokar.com/oss/hokusai/pdf/) |
| Tune concurrency and memory | [Runtime and performance](https://ivantokar.com/oss/hokusai/runtime-performance/) |
| Use Vapor or Hummingbird | [Integrations](https://ivantokar.com/oss/hokusai/integrations/) |
| Move from 0.x or between 2.x releases | [Migration](https://ivantokar.com/oss/hokusai/guide/migration/) |
| Read the API reference | [Hokusai on the docs site](https://ivantokar.com/oss/hokusai/reference/api/) · [DocC source](Sources/Hokusai/Hokusai.docc/Hokusai.md) |
| See what changed | [CHANGELOG.md](CHANGELOG.md) |

## Related projects

- [Hokusai Vapor](https://github.com/ivantokar/hokusai-vapor): Vapor adapter
- [Hokusai Hummingbird](https://github.com/ivantokar/hokusai-hummingbird): Hummingbird adapter
- [Hokusai examples](https://github.com/ivantokar/hokusai-examples): a web playground on Vapor and Hummingbird, and a macOS playground
- [Hokusai documentation](https://github.com/ivantokar/hokusai-docs): the documentation site's source

## Contributing

Design, scope and acceptance criteria live in GitHub issues; see [CONTRIBUTING.md](CONTRIBUTING.md) for the process, labels and pull request rules.

## License

MIT, see [LICENSE](LICENSE).
