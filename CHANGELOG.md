# Changelog

All notable changes to this project are documented in this file.

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
- `hokusai thumbnail` CLI command and `hokusai benchmark thumbnail` comparison benchmark.
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
- Documented CLI usage from source (`swift run hokusai ...`) and Homebrew installation flow.

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
