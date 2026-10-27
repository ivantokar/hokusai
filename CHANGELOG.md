# Changelog

All notable changes to this project are documented in this file.

## [Unreleased]

### Added (encoders, #23)
- Typed `heif(...)` (explicit `HEIFCompression`: HEVC or AV1), `tiff(...)` and
  still `gif(...)` encoders, with `.heic`/`.heif`/`.tif`/`.tiff`/`.gif`
  extension inference in `write(to:)`. `OutputFormat` gains `.heif`, `.tiff`
  and `.gif`; SVG is rejected as an output.
- Curated options with typed values and no raw native integers: JPEG
  `chromaSubsampling` and `optimizeCoding`; PNG `palette` (`PNGPalette`);
  WebP `alphaQuality`, `nearLossless`, `smartSubsample` and `preset`; AVIF
  `bitDepth` and `chromaSubsampling`; TIFF compression, predictor, tiling,
  pyramid and BigTIFF; GIF dither, effort, bit depth and interlace.
  `jpeg(options:)`, `png(options:)`, `webp(options:)`, `avif(options:)`,
  `heif(options:)` and `tiff(options:)` take the full value, so the short
  convenience signatures stay short.
- `RuntimeCapabilities` reports TIFF, GIF and HEIF output, and
  `heifCompressions` / `canEncode(_: HEIFCompression)` say which HEIF codecs
  this build can encode and decode (HEVC is often missing). An unavailable
  format or codec is `unsupported`, not a native failure.
- `RuntimeCapabilities.pngPalette` is verified by writing a palette PNG: on a
  libvips without a quantiser the option would be silently ignored, so it is
  `unsupported` instead.
- The CLI `convert` command accepts `heif`, `tiff` and `gif`.

### Fixed
- Writing a TIFF to a file failed ("bad seek"): the file target could not seek
  or read back. It now supports both, so every encoder works on both sinks.

### Changed (public API surface, #51)
- **Breaking:** `Hokusai.rgba(red:green:blue:opacity:)` is removed. Colour
  belongs to `Color`: `Color.sRGB8(red:green:blue:alpha:)` takes `UInt8`
  components, so out-of-range byte values cannot be written.
- **Breaking:** `OutputInfo.size` is `OutputInfo.byteCount`; `width` and
  `height` remain pixels.
- **Breaking:** PNG `progressive` is `interlaced` (`png(compressionLevel:interlaced:)`,
  `PNGOptions.interlaced`). JPEG keeps `progressive`.
- **Breaking:** `Hokusai.vipsVersion` and `Hokusai.version` are removed; the
  libvips version is `Hokusai.capabilities().libvipsVersion`.
- `OutputFormat`, the four encoder option structs and `Output` are `Equatable`.

### Removed (legacy API, #32)
- **Breaking:** `HokusaiImage`, `ImageBackend`, `ImageData`, `BackendType` and
  `VipsBackend`. `Hokusai` is the only image model; native ownership stays in
  the internal `NativeImage`, which releases its `VipsImage*` on deinit.
- **Breaking:** the `HokusaiLegacy` product and target.
- **Breaking:** `Hokusai.image(from:)`, `loadFromFile`, `loadFromBuffer`,
  `Hokusai.thumbnail(from:)`, the synchronous `toBuffer`/`toFile`/`toFormat`
  terminals, `extendedMetadata()`, and `magickVersion`.
- **Breaking:** the legacy option types `ResizeOptions`, `CropOptions`,
  `SaveOptions`, `ThumbnailOptions`, `ThumbnailCrop`, `Position`, `Kernel`,
  `FlipDirection` and `RotationAngle`. Use the typed `resize`, `extract`,
  `rotate` and encoder methods on `Hokusai`.
- The `vips_thumbnail` shims; `resize` already shrinks JPEG sources in the decoder.
- The CLI `--kernel` option now also accepts `mks2013` and `mks2021`.

### Changed (text)
- **Breaking:** text is a generated pipeline source. `Hokusai.text(_:layout:style:)`
  returns an ordinary immutable pipeline; `drawText(_:placement:layout:style:)`
  is sugar that composites it with the shared `Placement`/`Gravity` model.
  `TextOptions`, `TextGravity` and `drawText(_:x:y:options:)` are removed.
- **Breaking:** `TextContent.plain` escapes Pango markup characters, so any
  string is safe; `.markup` is the explicit opt-in.
- **Breaking:** `TextLayout` separates `.natural`, `.width(_:wrap:)` and
  `.fit(width:height:)`. Fit mode no longer passes a DPI, so libvips really
  fits the text to the box (the old wrapper always set `dpi`, which disabled it).
- **Breaking:** colours are `Color`, font files are `URL` (`TextStyle.fontFile`),
  and a path-like `font` string is rejected.
- **Breaking:** `kerning` and `antialiasing` are removed; they never did anything.
- `lineHeight` is a multiple of the font's natural line pitch. The old
  `lineSpacing` converted to the wrong unit. Added `justify` and `TextWrap`.
- Stroke is one dilation and shadow one blur, blended with a single composite.
  The old outline composited the text once per neighbouring pixel.
- Rotation reuses the geometry transform. Text opacity is applied after
  rendering, so `opacity: 0` text is transparent (Pango drew it opaque) and
  shadows follow the glyph shape.

### Changed (composition)
- **Breaking:** `CompositeLayer` takes a typed `Placement` (`.at(x:y:)`,
  `.gravity(_:offsetX:offsetY:)`, `.tile(gravity:)`); `CompositeLayer(_:x:y:)`
  stays as a shorthand for exact coordinates. `CompositeLayer(data:)` is
  removed: build the layer with `Hokusai(data:)`.
- **Breaking:** `CanvasAnchor` is now `Gravity`, shared by `extend(to:)`, PDF
  page options and layer placement.
- `BlendMode` grows from three modes to the full libvips Porter-Duff and PDF
  set (25 modes, `CaseIterable`).
- `composite(_:space:)` blends every layer with one `vips_composite` call
  instead of a `vips_composite2` chain, and no longer forces inputs to 8-bit
  RGBA: libvips normalises colour and alpha, and opacity scales the alpha band
  in the layer's own bit depth. `space: .linear` blends in linear light.
- Gravity offsets are inward padding at edges and a signed shift on a centred
  axis; coordinates beyond ±10,000,000 are rejected when the layer is added.

### Changed (effects)
- **Breaking:** `normalize()` is now photographic contrast stretching,
  `normalize(lower: 1, upper: 99)`: the luminance range between two
  percentiles is stretched to the full range, with the same linear map on every
  colour band, alpha untouched. It previously called `vips_hist_norm`, which
  normalises a histogram image and is not an image operation.
- **Breaking:** `removeAlpha()` takes no argument and drops the alpha band
  without compositing. It used to flatten onto a background; that is still
  `flatten(background:)`.
- **Breaking:** `grayscale()` is a visual effect that keeps RGB(A) and alpha.
  The single-colour-channel result is `convert(to: .grayscale)`, which also
  keeps alpha as a second band.
- `tint(_:)` preserves alpha instead of returning an opaque RGB image.
- `blur` and `sharpen` run with alpha handled correctly: blur weights colour by
  alpha so transparent pixels do not bleed. `blur` gained `precision` and
  `minAmplitude`; `sharpen(_:)` takes a `SharpenOptions` (`sigma`, `flat`,
  `jagged`, `threshold`, `maxBrightening`, `maxDarkening`).
- `ensureAlpha(opacity:)` appends constant alpha of the given opacity.
- `flatten` is a no-op without alpha and works for grey+alpha images.
- `grayscale()`, `negate()` and `removeAlpha()` no longer throw.

### Fixed
- `resize(fit: .contain)` and `extend(to:)` failed with a transform error on
  images without an alpha channel (for example JPEG) because the RGBA fill was
  passed unchanged; the fill is now converted to the image's own bands, and
  16-bit images use the 16-bit range.
- `rotate(by:)` no longer traps on very large angles.
- `.avif().data()` returned HEVC-coded HEIC bytes because the buffer encoder
  used libvips' default codec; it now produces AV1 AVIF and honours `effort`
  and `lossless`. File output no longer depends on the `.avif` suffix to pick
  AV1.

### Added
- New effects: `gamma(_:)` (runs where written, never reordered around resize),
  `negate(alpha:)`, `median(size:)`, `threshold(_:grayscale:)`,
  `modulate(brightness:saturation:hue:)` (LCH), and `clahe(width:height:maxSlope:)`
  (adaptive contrast per colour band, 8-bit).
- Shrink-on-load behind the normal `resize`. When a JPEG file or `Data` source
  starts with `resize` (optionally after `autoOrient`) and the decoded image
  would still have at least the pixels the resize needs, the decoder shrinks it
  by 2, 4 or 8 before the remaining resample. Output dimensions are computed
  from the full-resolution header, so they are exactly those of a normal decode
  and resize; pixel values agree within codec tolerance. Any other operation
  first, any other codec, an explicit `InputOptions.page`, or a source already
  built for another consumer in the same evaluation keeps the normal path. No
  API change. Measured on a 6000×4000 JPEG resized to 400×400 WebP (including
  encoding, libvips cache bypassed): 31 ms to 14 ms for a smooth 0.7 MB file,
  102 ms to 82 ms for a noise-dense 14 MB file, whose entropy decoding the
  shrink cannot skip.
- Geometry on the evaluator: `extend(top:left:bottom:right:mode:)` and
  `extend(to:anchor:mode:)` with `ExtendMode` (`.background`, `.copy`,
  `.repeat`, `.mirror`); `rotate(by:background:interpolation:)` using
  `vips_rotate` with a typed `Interpolation`; `affine(_:inputOffset:outputOffset:outputArea:edges:interpolation:)`
  with `AffineMatrix`; and the `mks2013`/`mks2021` resize kernels (libvips
  8.17+, `unsupported` on older builds). `extract` rejects negative offsets
  when the step is added.
- `Hokusai.configure(_:)` with `RuntimeConfiguration`: process-wide
  `maxConcurrentEvaluations`, `maxQueuedEvaluations`, and `vipsConcurrency`,
  frozen at first runtime use.
- `Hokusai.capabilities()` reports decodable/encodable formats, the libvips
  version, and text rendering for the linked build; `hokusai info` prints it.
- `Hokusai.runtimeStatus` reports queued/active evaluations and effective
  limits without initializing libvips.
- `HokusaiError.resource(ResourceFailure)` for configured limits, starting
  with `maxQueuedEvaluations` (kind `.queuedEvaluations`).

### Changed (output metadata)
- **Breaking:** `preserveMetadata()` and `removeMetadata()` are replaced by
  `metadataPolicy(_:)` with a typed `MetadataPolicy` (`exif`, `icc`, `xmp`,
  `iptc`, `other`, `orientation`, `density`), plus `.default`, `.preserveAll`,
  and `.removeAll`. Modern encoders pass libvips' native `keep` flags instead
  of the legacy `strip` boolean.
- **Breaking (behavior):** the default no longer removes everything. EXIF, XMP,
  IPTC, and comments are still removed, but the ICC profile, orientation, and
  density are now kept, so outputs can be slightly larger and wide-gamut images
  keep their colours. Use `.removeAll` for the old output.
- Removing EXIF while keeping orientation keeps a minimal EXIF block holding
  the orientation. Removing orientation deletes the tag without rotating
  pixels.
- CLI: `convert` without `--strip-metadata` now applies the library default
  instead of preserving everything; `--strip-metadata` means `.removeAll`.

### Changed (PDF)
- **Breaking:** `PDFPageSize` is `.image(dpi:)`, `.a4(_:)`, `.letter(_:)`,
  `.points(width:height:)`. The global `dpi` argument of `pdf(pageSize:dpi:)`
  is gone: it only ever affected `.image`, and was silently ignored for A4,
  Letter, and custom pages. `PDFOptions` gains `margins`, `anchor`,
  `background`, `maxEffectiveDPI`, and `metadata`; `pdf(...)` takes them
  directly.
- **Breaking:** `OutputInfo` has a `pdf` property (page count and first-page
  size in points). For PDF, `width` and `height` are the embedded raster pixels.
- PDF is written through Cairo's stream surface into the same sink semantics
  as the other formats: `write(to:)` no longer builds the whole document as
  `Data`, write failures are `io(.write)`, a cancelled or failed write removes
  the partial file, and cancellation throws `CancellationError`.
- The raster is converted into a single buffer (libvips to 8-bit sRGB RGBA,
  then premultiplied in place) instead of two, lowering peak memory by one
  raster. Encoded bytes are no longer copied three times.
- Cairo failures carry Cairo's own status text as the diagnostic and no longer
  go through libvips' global error log. The Cairo bridge lives in `CCairo`, not
  `CVips`.
- Transparency is kept unless a `background` is given.

### Changed (metadata)
- **Breaking:** `Hokusai.metadata()` is `async` and describes the **root source**
  only, never the transformed pipeline. Composite pipelines report their base
  source. Inspection reads the header on Hokusai's evaluation scheduler and
  honours `InputOptions` (page, limits, access).
- **Breaking:** `ImageMetadata` is reshaped. Typed `ImageOrientation` (1...8)
  replaces the raw integer, with `orientedSize`; `PixelMetadata`
  (`channels`, `hasAlpha`, `interpretation`, `sampleFormat`, `bitsPerSample`,
  `isPalette`) replaces `channels`, `hasAlpha`, `space`, and `colorSpace`;
  one `density` in DPI with `densityUnit` replaces `density` and `densityXY`;
  `PageMetadata` and `AnimationMetadata` replace `pages`, `pageHeight`, and the
  page-count-based `isAnimated`; `sourceByteSize` replaces `size`; and `iptc`,
  `isProgressive`, and `chromaSubsampling` are new.
- Fixed: `isAnimated` was true for any multi-page source (TIFF, PDF); it now
  requires frame delays. `size` read libvips' `sizeof_header`, which is not the
  source's byte size. Format detection no longer strips `load` from the loader
  name, so AVIF is no longer reported as HEIF.
- `HokusaiImage.extendedMetadata()` stays only for the legacy handle and is
  removed with it (#32).

### Fixed (output)
- `data()` ignored `progressive` for JPEG and PNG, so the same configuration
  produced a baseline JPEG in memory but a progressive one in a file (and
  likewise a non-interlaced versus an interlaced PNG). Modern output no longer
  goes through the legacy save options: each encoder has one native lowering
  that serves the memory and file sinks, so options cannot reach one and miss
  the other.

### Changed (output)
- Raster formats are encoded through libvips targets: `data()` takes the
  encoded buffer without copying it, and `write(to:)` writes straight to the
  file.
- A failed `write(to:)` for JPEG, PNG, WebP, and AVIF now reports
  `HokusaiError.io` with a write operation and the system error when the
  destination cannot be opened or written, instead of a generic `encode`
  error. The file is created on the first write, and a regular file that was
  being written is removed if the write fails.
- `OutputInfo.size` for `write(to:)` is the number of bytes written.

### Changed (planning)
- Pipelines are lowered by a small planner that keeps every written operation
  in written order. Rotations by whole turns and empty composites are skipped
  as proven identities, and within one evaluation a source or composite layer
  shared by several consumers (a logo used twice, or a layer derived from the
  base image) is opened and built once. Sources opened with `.sequential`
  access are never shared. Output is unchanged; nothing is cached between
  evaluations.

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
