# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Fixed
- `.avif().data()` returned HEVC-coded HEIC bytes because the buffer encoder
  used libvips' default codec; it now produces AV1 AVIF and honours `effort`
  and `lossless`. File output no longer depends on the `.avif` suffix to pick
  AV1.

### Added
- `Hokusai.configure(_:)` with `RuntimeConfiguration`: process-wide
  `maxConcurrentEvaluations`, `maxQueuedEvaluations`, and `vipsConcurrency`,
  frozen at first runtime use.
- `Hokusai.capabilities()` reports decodable/encodable formats, the libvips
  version, and text rendering for the linked build; `hokusai info` prints it.
- `Hokusai.runtimeStatus` reports queued/active evaluations and effective
  limits without initializing libvips.
- `HokusaiError.resource(ResourceFailure)` for configured limits, starting
  with `maxQueuedEvaluations` (kind `.queuedEvaluations`).

### Changed (input)
- **Breaking:** `InputOptions` is the single encoded-input policy and is now
  applied: `access` (from the former `LoadOptions`), `failOn` (now with
  `.truncated`, passed to libvips and defaulting to `.warning`), `page`
  (one page), `limits` (`maxBytes`, `maxPixels`, `maxChannels`), and
  `revalidate`. Previously every non-default value was rejected.
- **Breaking:** `LoadOptions` is removed; the legacy static loaders take
  `InputOptions`. `InputOptions.pages` and `Hokusai(path:)` are removed.
- **Breaking (behavior):** the `.warning` default is now enforced, so inputs
  with decoder warnings (for example a PNG with a bad chunk checksum) fail
  with `HokusaiError.decode`. Use `failOn: .none` to restore the old leniency.
- `HokusaiError.resource` kinds `encodedBytes`, `decodedPixels`, `channels`.
- Decoder failures that only appear while pixels are read (truncated files)
  are reported as `decode`, labelled with the source, instead of `encode`.

### Changed (errors)
- **Breaking:** `HokusaiError` is one taxonomy: `invalidInput(reason:)`,
  `invalidOption`, `unsupported(feature:reason:)`, `decode`, `transform`,
  `encode`, `io`, `resource`, `runtime`. Each boundary classifies its own
  failures; nothing is inferred from native error text.
- **Breaking:** `FailureContext.message` is split into a Hokusai-owned
  `reason` and an optional, best-effort native `diagnostic`.
- Composite layer failures are labelled with their layer, for example
  `composite layer 2 / decode input data`.
- Legacy `HokusaiImage` APIs throw the same modern cases.

### Removed
- **Breaking:** legacy `HokusaiError` cases `initializationFailed`,
  `loadFailed`, `saveFailed`, `invalidOperation`, `invalidDimensions`,
  `unsupportedFormat`, `conversionFailed`, `textRenderingFailed`,
  `vipsError`, `magickError`, `memoryAllocationFailed`, `fileNotFound`,
  `invalidImageData`, and `notSupported`.
- **Breaking:** `Hokusai.vipsConcurrency`. Set
  `RuntimeConfiguration.vipsConcurrency` via `configure(_:)` at startup.
- **Breaking (CLI):** `hokusai benchmark pipeline --concurrency-sweep`. Run one
  process per `--vips-concurrency` value instead.
- **Breaking:** `HokusaiError.cancelled`. Cancelled terminals throw Swift's
  `CancellationError`.
- **Breaking:** `Hokusai.shutdown()`. libvips is now process-scoped: it is
  initialized at most once and stays available until the process exits.
  Remove calls to `shutdown()`; the operating system reclaims native resources
  at exit.

### Changed
- **Breaking (behavior):** pipelines are lazy. `Hokusai(data:)`, `Hokusai(url:)`
  and transforms only record intent; the source is opened and the libvips
  graph built inside `data()`/`write(to:)`. Decode failures, missing files, and
  pixel-dependent errors (e.g. `extend` to a smaller canvas) are now thrown by
  the terminal (or `metadata()`). Option validation is still immediate, and
  output pixels are unchanged.
- Terminal evaluations are admitted by an asynchronous FIFO scheduler: callers
  beyond the concurrency limit wait as suspended tasks instead of blocking
  threads. Cancelling the calling task now also stops running libvips work.
- Composite layers contribute only their image transformations; a layer's
  encoder and metadata settings are ignored.
- **Breaking:** the native baseline is now libvips 8.16+ and Cairo 1.16+.
  Older libraries are rejected at compile time instead of failing on missing
  symbols. The previously documented libvips 8.9 minimum was no longer true.
- Swift 6.4 is a supported, CI-tested toolchain; the minimum stays Swift 6.0.
- `HokusaiNIO` depends on `NIOFoundationCompat` for its `Data` conversions.
- CI pins and reports the exact Swift, libvips, and Cairo versions it tests.

## [1.0.0] - 2026-08-05

### Added
- Immutable `Hokusai` pipelines with typed `Data`, file-`URL`, and optional
  SwiftNIO `ByteBuffer` inputs.
- Async `data()` and `write(to:)` terminals, typed JPEG/PNG/WebP/AVIF encoders,
  typed composition, geometry, colour, alpha, and metadata APIs.
- Cairo-backed one-page PDF output via `.pdf(pageSize:dpi:)`, including file
  extension inference and `hokusai convert --output document.pdf`.
- `HokusaiLegacy` product for intentional, temporary 0.x adapter imports.

### Changed
- **Breaking:** the recommended API is now `Hokusai(data:)` or `Hokusai(url:)`.
  Processing returns immutable values; terminal encoding and file writes are
  asynchronous. See the README's 0.x-to-1.0 migration table.
- Output metadata is removed by default; use `preserveMetadata()` only when a
  downstream consumer needs embedded metadata.

### Compatibility
- The optimised `thumbnail` CLI command continues to use the intentionally
  retained legacy thumbnail loader while its public 1.0 pipeline counterpart is
  designed. All other primary CLI transforms use the 1.0 pipeline.

## [0.3.0] - 2026-07-15

### Added
- Thumbnail API backed by `vips_thumbnail`: `Hokusai.thumbnail(from:width:options:)` for file paths and buffers, and `HokusaiImage.thumbnail(width:options:)` for already-loaded images, with `ThumbnailOptions` (height bound, `centre`/`attention`/`entropy` crop, `noRotate`) and EXIF auto-rotation by default.
- `LoadOptions` with `AccessMode` (`random`/`sequential`) exposing the libvips access-pattern hint, plus the `.sequential` preset.
- `Hokusai.vipsConcurrency` for reading/setting the libvips thread pool size.
- `hokusai thumbnail` CLI command.
- `HokusaiError.invalidDimensions` for centralized dimension validation (positive, `Int32`-safe; crop strategies require an explicit height).
- GitHub Actions CI: build, tests, release CLI build, and CLI smoke tests on macOS and Linux (Swift 6.0/6.1).
- Realistic test fixtures and an expanded suite (62 tests): geometry, crop strategies, EXIF orientation, error semantics, lifecycle, and concurrency.

### Changed
- **Breaking:** `Hokusai.image(from:)` is no longer declared `async` — it always performed synchronous libvips work; the misleading marker was removed. Replace `try await Hokusai.image(...)` with `try Hokusai.image(...)`.
- `Hokusai.initialize()` is now idempotent and thread-safe, and is called automatically by loading entry points. `Hokusai.shutdown()` is documented as a final, advanced process-teardown operation; re-initialization after shutdown throws.
- Buffer loads copy their input bytes, so a `Data` passed to Hokusai no longer needs to outlive the returned image.
- Tests migrated from XCTest to swift-testing (swift-corelibs-xctest has an unresolved RunLoop deadlock on Linux with large test targets).

### Fixed
- Use-after-free when loading from buffers: libvips does not copy `vips_image_new_from_buffer` input, but pointers only valid inside `Data.withUnsafeBytes` were passed to a lazily decoded pipeline.
- Width-only thumbnails of portrait sources returned a width smaller than requested (`vips_thumbnail` defaults an unset height to `width`).
- libvips error messages were cleared before being read, losing diagnostics and racing other threads.
- Corrected access-mode and shrink-on-load documentation (plain `resize` never shrinks on load; WebP has shrink-on-load, PNG does not) and broken README examples.

### Requirements
- libvips 8.9 or newer.
- `prompt` 1.1.2 or newer (Linux build fix) for the CLI target.

## [0.2.1] - 2026-04-21

### Added
- Added first-party `hokusai` CLI target.
- Documented CLI usage (`hokusai ...`) and Homebrew installation flow.

### Notes
- This release builds on the native-backend migration introduced in `0.2.0`.
- ImageMagick is no longer required at runtime.

## [0.2.0] - 2026-04-20

### Changed
- Removed ImageMagick as a required dependency and moved to the libvips runtime/backend.
- Updated CI and release workflows to install only libvips + pkg-config.
- Updated README installation, architecture, and platform notes to describe the native image runtime.

### Compatibility
- Preserved public API shape for legacy `magickVersion` and `HokusaiError.magickError` as deprecated compatibility shims.
- No ImageMagick runtime/backend support remains.

## [0.1.2] - Previous

- Previous release.
