# Hokusai – libvips Integration Notes

## Background

This document records an investigation into several open questions about the libvips integration:

- Is the current binding approach appropriate for a Swift library?
- Should Hokusai expose the `access="sequential"` load mode?
- Should Hokusai expose a dedicated thumbnail API?
- Are there shrink-on-load optimisations that the current resize path misses?

It records what was inspected, what changed, what the benchmarks showed, and what did not improve.

## Links Checked

- [libvips language bindings guide](https://www.libvips.org/API/current/binding.html)
- [How libvips opens files](https://www.libvips.org/API/current/how-it-opens-files.html)
- [libvips developer checklist](https://www.libvips.org/API/current/developer-checklist.html)
- [vips_thumbnail](https://www.libvips.org/API/current/ctor.Image.thumbnail.html)
- [vips_thumbnail_buffer](https://www.libvips.org/API/current/ctor.Image.thumbnail_buffer.html)

libvips version tested: **8.18.2** (Homebrew, macOS).

---

## Task 1: What the Implementation Looked Like Before Changes

### Binding layer

Hokusai bridges libvips via a thin C shim (`Sources/CVips/shim.h`) exposed to Swift through a `systemLibrary` target (`CVips`). Every libvips call is wrapped in a `static inline` C function. Swift code calls these wrappers and never touches libvips directly. Memory is managed by `g_object_unref` in `VipsBackend.deinit`.

### Image loading

`VipsBackend.loadFromFile` called `vips_image_new_from_file(path, NULL)` — no access mode, no extra options. The libvips default (`VIPS_ACCESS_RANDOM`) was always used.

`VipsBackend.loadFromBuffer` called `vips_image_new_from_buffer(buf, size, "", NULL)` — same default.

### Resize

`Resize.swift` called `vips_resize(in, out, hscale, "vscale", vscale, "kernel", kernel)`. This is a pipeline-based approach: libvips constructs a lazy evaluation graph, and pixels are pulled on demand. No explicit use of `vips_thumbnail` or its shrink-on-load path.

### Save / export

Format-specific save functions (`vips_jpegsave`, `vips_webpsave`, etc.). No issues found.

### Benchmark

The existing benchmark suite had: `resize:1200x800`, `convert:webp:q80`, `rotate:33`, `text:stroke-shadow`. The table showed Mean, P95, Ops/s only — Median, Min, Max were missing.

### What was missing

- No `access` option exposed to callers.
- No `vips_thumbnail` / `vips_thumbnail_buffer` usage anywhere.
- No `VipsAccess` type exported to Swift.

---

## Task 2: Binding Approach Assessment

### Is it acceptable?

Yes, for the current scope. The thin-shim approach is the simplest correct way to call libvips from Swift. It is honest (no hidden state), easy to audit, and avoids the complexity of a GObject introspection layer.

### Risks of keeping manual C wrappers

- Every new libvips option requires a new C shim. Options not in the shim are silently lost.
- The `G_GNUC_NULL_TERMINATED` variadic API makes it impossible to call libvips operations generically from Swift — each operation needs its own wrapper.
- As the operation surface grows, `shim.h` will become a maintenance burden.

### Could a GObject-based layer replace this?

Possibly, but not without significant work. A GObject introspection layer (as used by the Python and Ruby bindings) would allow calling any operation by name with a dictionary of options. This would eliminate per-operation C wrappers. However, it requires either:
- Runtime introspection via GIR/GObject typelib at process start, or
- A generated Swift binding layer from the GIR metadata.

Neither is a small weekend project. The existing shim is the right choice for now.

### What can be improved without a full rewrite

- Expose `access` mode so callers can opt into sequential loading (done).
- Expose `vips_thumbnail` family as a separate API (done).
- Document the operation path used in benchmarks so future maintainers can see what libvips call is behind each case (done).

---

## Task 3: Sequential Access

### What was added

- `AccessMode` enum: `.random` (default) and `.sequential`
- `LoadOptions` struct with `access: AccessMode` and a `.sequential` static preset
- `Hokusai.image(from:options:)`, `Hokusai.loadFromFile(_:options:)`, and `Hokusai.loadFromBuffer(_:options:)` now accept `LoadOptions`
- Two new C shim functions: `swift_vips_image_new_from_file_sequential` and `swift_vips_image_new_from_buffer_sequential`
- Default is unchanged: all existing callers continue to use random access without modification

### What sequential access is for

When sequential access is set, libvips decodes the image as a top-to-bottom stream and holds only a small window of rows in memory at once. This lowers peak RSS for large images processed in a forward-only pipeline (load → resize → save to buffer, for example).

### What the benchmarks showed

**Benchmark: 4000×3200 JPEG → 400×320 (10× downscale, warm file cache)**

| Case | Op path | Access | Mean | Ops/s |
|------|---------|--------|------|-------|
| resize:default | vips_resize | random | 2.73 ms | 366 |
| resize:sequential | vips_resize | sequential | 21.74 ms | 46 |
| thumbnail:file | vips_thumbnail | n/a | 10.01 ms | 100 |

Sequential access was 8× slower than random access for this case.

**Why sequential is slower for JPEG downscaling**

Neither access mode changes *what* is decoded — `vips_resize` after a plain
load always decodes the full pixel grid. (Shrink-on-load only happens when the
loader is given a shrink/scale argument, which only the `vips_thumbnail`
family does; see Task 4.) The difference is in how the decode is buffered and
parallelised: with random access the full decode result (memory buffer or disk
temp file, per `vips-disc-threshold`) is available to all worker threads;
sequential access forces the pipeline through an ordered, single-window
streaming read, which serialises work the random-access path can parallelise.
The 8× figure is a measurement on this machine, not a universal constant.

### When sequential access may help

- Very large source files where you want to reduce peak RSS under load.
- Pipelines that genuinely read the image once, top-to-bottom (e.g. encode to buffer immediately after load).

### When sequential access does not help (and may hurt)

- Heavily downscaled JPEG pipelines (measured significantly slower here).
- Operations that need out-of-order pixel access: rotation by non-90° multiples, flips, smart crop, compositing with an offset. Requests *ahead* of the read point are handled by decoding forward, but requests *behind* the small line window fail with a libvips error — there is no silent fallback to random access (verified against `libvips/conversion/sequential.c`).
- Small images: the streaming bookkeeping is not worth the memory saving.

**The recommendation:** keep the default (`random`) unless you have measured that peak RSS is a problem and your pipeline is genuinely sequential.

---

## Task 4: Thumbnail API

### What was added

**C shim (`shim.h`)**

Three new shim functions:
- `swift_vips_thumbnail(filename, out, width, height, crop, no_rotate)`
- `swift_vips_thumbnail_buffer(buf, len, out, width, height, crop, no_rotate)`
- `swift_vips_thumbnail_image(in, out, width, height, crop, no_rotate)`

Each wraps the corresponding `vips_thumbnail*` family with conditional variadic arguments for the height, crop, and no-rotate options.

**Swift model types**

- `ThumbnailCrop` enum: `.none`, `.centre`, `.attention`, `.entropy`
- `ThumbnailOptions` struct: `height`, `crop`, `noRotate`

**Public API**

```swift
// Static (file path) — enables shrink-on-load for JPEG/TIFF/HEIF
Hokusai.thumbnail(from path: String, width: Int, options: ThumbnailOptions = .init()) throws -> HokusaiImage

// Static (buffer)
Hokusai.thumbnail(from data: Data, width: Int, options: ThumbnailOptions = .init()) throws -> HokusaiImage

// Instance method (already-loaded image, no shrink-on-load benefit)
HokusaiImage.thumbnail(width: Int, options: ThumbnailOptions = .init()) throws -> HokusaiImage
```

### Why thumbnail is separate from resize

`vips_resize` and `vips_thumbnail` are different operations with different trade-offs:

| | `vips_resize` | `vips_thumbnail` |
|-|--------------|-----------------|
| Kernel control | Explicit (nearest/lanczos3/etc.) | Automatic (chosen by libvips) |
| Fit modes | inside/outside/fill/cover/contain | Width-bound or width+height-bound |
| Shrink-on-load | None (loader decodes the full grid) | Yes: header read first, then the source re-opened with a computed shrink/scale factor |
| EXIF auto-rotate | Requires explicit `autoRotate()` | Applied by default |
| Crop | Via separate smartcrop | Integrated (`crop=attention/entropy`) |

Shrink-on-load support by format (verified against `libvips/resample/thumbnail.c`):
JPEG (decoder shrink 1/2/4/8), WebP (decode-time scale via libwebp), TIFF
(pyramid/subifd levels), HEIF (embedded thumbnail), PDF/SVG (render scale),
OpenSlide (pyramid level), JP2K (page pyramids). **PNG has no shrink-on-load.**

`vips_thumbnail` is designed as a "do the right thing" operation for thumbnail generation. It handles EXIF rotation, selects an appropriate downscale kernel, and integrates shrink-on-load. `vips_resize` is appropriate when you need explicit kernel control or the fit modes (contain, cover) that `vips_thumbnail` does not provide.

### What the benchmarks showed

**Benchmark: 4000×3200 JPEG → 1200×800 (3.3× downscale, warm file cache)**

| Case | Op path | Mean | Ops/s |
|------|---------|------|-------|
| resize:default:1200x800 | vips_resize | 6.58 ms | 152 |
| thumbnail:file:1200x800 | vips_thumbnail | 15.04 ms | 66 |
| thumbnail:file:1200 (width-only) | vips_thumbnail | 28.91 ms | 35 |
| resize:sequential:1200x800 | vips_resize+sequential | 29.36 ms | 34 |

**Benchmark: 1000×800 JPEG → 1200×800 (upscale, warm file cache)**

| Case | Op path | Mean | Ops/s |
|------|---------|------|-------|
| resize:default:1200x800 | vips_resize | 3.84 ms | 260 |
| thumbnail:file:1200x800 | vips_thumbnail | 4.26 ms | 235 |
| thumbnail:file:1200 | vips_thumbnail | 5.12 ms | 195 |
| resize:sequential:1200x800 | vips_resize+sequential | 4.50 ms | 222 |

### Interpreting the results

On warm file-cache benchmarks on this machine (12-core macOS, libvips 8.18.2), `vips_thumbnail` was consistently slower than `vips_resize` with random access, ranging from 15–55% slower for the upscale case and 2–4× slower for the 3.3× downscale case.

**Why this happened**

Two effects dominate in a tight warm-cache loop:

1. The libvips *operation cache* caches loader operations keyed on the
   filename. A benchmark loop that loads the same file repeatedly mostly reuses
   the cached decode, so the full-decode cost of the plain-load path is
   amortised away. Production workloads with many unique files do not get this
   effect.
2. `vips_thumbnail` reads the image header, computes the optimal shrink factor,
   and then opens the file a second time with that factor set (verified in
   `libvips/resample/thumbnail.c`). On a warm OS page cache the extra header
   read and second open add latency that shrink-on-load cannot repay, because
   the competing plain load is served from caches anyway.

In other words: these numbers say "warm-cache repeat loads of one file favour
`vips_resize`", not "`vips_thumbnail` is slow". Cold-cache and storage-bound
workloads shift the balance toward `vips_thumbnail`.

**When `vips_thumbnail` would win**

- **Cold file cache**: `vips_thumbnail` reads less data from disk on the first access (it uses the JPEG shrink factor to request fewer scan lines from the file). On a storage-bound server with many unique files, this can matter.
- **EXIF rotation**: `vips_thumbnail` handles EXIF orientation automatically. If your source images may be rotated by camera EXIF data and you do not call `autoRotate()` separately, thumbnail avoids producing sideways images.
- **Integrated crop**: combining shrink and smart-crop in one call (`ThumbnailOptions(height: 800, crop: .attention)`) is convenient and correct.

### What did not improve

Throughput on warm-cache JPEG downscaling did not improve with `vips_thumbnail`. The `resize:default` path remains the fastest for high-throughput in-memory pipelines on cached files.

---

## Task 5: Benchmark Extension

The suite and thumbnail benchmark commands now report:

**Environment panel**: libvips version, concurrency, CPU count, input dimensions, bands, alpha.

**Table columns**: Case, Mean, Median, P95, Min, Max, Ops/s.

New benchmark cases added:
- `thumbnail:file:1200` — `vips_thumbnail`, width-only bound
- `thumbnail:file:1200x800` — `vips_thumbnail`, width+height bound
- `resize:sequential:1200x800` — sequential load + `vips_resize`

New dedicated benchmark: `hokusai benchmark thumbnail` — head-to-head comparison of all resize/thumbnail paths with Op path and Access mode columns.

---

## Risks and Limitations

### Sequential access and JPEG

Sequential access made heavily downscaled JPEG pipelines ~8× slower on the benchmarks above (serialised streaming decode vs. parallel access to a full decode; shrink-on-load is not a factor in either resize path). This is documented in `LoadOptions.swift` and in this file.

### `vips_thumbnail` throughput

On warm-cache benchmarks, `vips_thumbnail` is slower than `vips_resize` with random access. It is correct to expose it (EXIF rotation, cold-cache scenarios, integrated crop) but it should not be marketed as "faster" for all workloads.

### Benchmark file cache state

All benchmarks above were run with the test files already in the OS page cache (warm cache). Cold-cache results — which would favour `vips_thumbnail` — were not measured. Production workloads may differ substantially.

### No memory measurements

The benchmarks measure wall-clock time only. Peak RSS under load (the main benefit of sequential access) was not measured here. If peak memory matters for your deployment, profile it with your own workload.

### C shim coverage

The shim exposes the `height`, `crop`, and `no-rotate` options for `vips_thumbnail`. Other options (`size`, `linear`, `import-profile`, `export-profile`, `intent`, `fail-on`) are not exposed. Add them to the shim when needed.

---

## Hardening Pass (July 2026)

A follow-up pass tightened correctness, lifecycle, and documentation before
merge. Summary of the changes and their rationale:

### Minimum libvips version: 8.9

The shim now uses `vips_source_new_from_blob`, `vips_image_new_from_source`,
`vips_thumbnail_source`, and `vips_error_buffer_copy`, all introduced in
libvips 8.9 (January 2020). Ubuntu 20.04's `libvips-dev` (8.9) and anything
newer qualifies.

### Buffer ownership

`vips_image_new_from_buffer()` does **not** copy the bytes it is given; the
caller must keep them alive until the image and its whole pipeline close.
The previous code passed a pointer that was only valid inside
`Data.withUnsafeBytes`, which is a use-after-free once pixels are pulled
lazily. All buffer loads (plain, sequential, and `thumbnail_buffer`) now copy
the bytes into a `VipsBlob` (`vips_blob_copy`) and load through a
`VipsSource`; libvips frees the copy when the last pipeline reference drops.
Cost: one memcpy per buffer load. Public consequence: `Data` passed to
Hokusai never needs to outlive the returned image, and this is covered by a
regression test that clobbers the source `Data` before pulling pixels.

### Error buffer

`getLastError()` previously called `vips_error_clear()` *before* copying the
message, losing the text and racing with other threads. It now uses
`vips_error_buffer_copy()`, which copies and clears atomically.

### Width-only thumbnails

`vips_thumbnail` defaults an unset `height` to `width` (a square bound), so
"width-only" thumbnails of portrait sources came out narrower than requested.
The shim now passes `VIPS_MAX_COORD` as the height when no height is given,
making width-only behave as documented: output width = requested width,
height follows the aspect ratio.

### Lifecycle

`initialize()` is idempotent and thread-safe (lock-guarded state machine),
and all load entry points call it automatically. `shutdown()` is documented
as a final, advanced process-teardown operation: it cannot be undone,
repeated calls are no-ops, and re-initialization afterwards throws.

### Validation and error semantics

All thumbnail entry points (file, buffer, existing image, CLI) validate
dimensions centrally: width/height must be positive and fit `Int32`;
crop strategies require an explicit height. Violations throw
`HokusaiError.invalidDimensions`. Native failures preserve the libvips
diagnostic text behind stable, categorised errors (`fileNotFound`,
`invalidImageData`, `loadFailed` for decode/load, `vipsError` for
transformations on already-loaded images).

### Test framework: swift-testing

The suite uses swift-testing rather than XCTest. swift-corelibs-xctest has a
known unresolved deadlock on Linux when a target contains many test methods
(swiftlang/swift-corelibs-xctest#504): the generated runner wraps every test
in an async expectation wait, and the RunLoop-based waiter loses the wakeup
nondeterministically. Reproduced here on Swift 6.0, 6.1, and 6.2 containers —
`swift test` hung at a random test each run. The same 62 tests pass reliably
under swift-testing on both macOS and Linux.

### Synchronous loading API

`Hokusai.image(from:)` was declared `async` while performing synchronous
libvips work on the caller's executor — a fake-async signature. It is now
synchronous. The ergonomic API milestone will define the library's
terminal execution and concurrency policy (e.g. where decode work is
offloaded); until then callers own that decision.

---

## Should GObject/Operation-Based Bindings Be Explored?

Yes, eventually. The current shim approach requires a new C wrapper per option combination. As Hokusai adds more operations, `shim.h` will grow and the maintenance cost rises.

A GObject-based layer (calling `vips_call` or using GIR typelib data) would allow any operation to be invoked by name with a dictionary of options — no per-operation C code. The Ruby vips gem and the Python pyvips library use this approach.

This is not urgent now. The current shim has ~400 lines and is still manageable. Revisit when either:
- The shim exceeds ~800 lines, or
- A feature genuinely requires runtime-dynamic operation dispatch.

---

## Open Questions

1. Should `ThumbnailOptions` expose `size` (VipsSize: up-only, down-only)? Omitted now to keep the API small.
2. Should `LoadOptions` support `fail-on` (VipsFailOn) for controlling how broken images are handled on load?
3. Should the benchmark runner include peak RSS measurement (via `getrusage`) for sequential-vs-random comparisons?
4. Does `vips_thumbnail` performance relative to `vips_resize` change on storage-bound Linux servers vs. the macOS development machine used here?
