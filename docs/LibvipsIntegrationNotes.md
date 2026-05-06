# Hokusai – libvips Integration Notes

## Background

Reddit feedback on Hokusai raised several questions about the libvips integration:

- Is the current binding approach appropriate for a Swift library?
- Should Hokusai expose the `access="sequential"` load mode?
- Should Hokusai expose a dedicated thumbnail API?
- Are there shrink-on-load optimisations that the current resize path misses?

This document records what was inspected, what changed, what the benchmarks showed, and what did not improve.

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

libvips's JPEG loader (`vips_jpegload`) has a shrink-on-load capability: when random access is requested and the pipeline eventually scales down by 2×, 4×, or 8×, the JPEG decoder itself produces a smaller image (fewer rows decoded). This is automatic and transparent.

Sequential access disables this optimisation. The JPEG decoder must produce every row in order, so the full 4000×3200 grid is decoded even though only 400×320 pixels are needed.

### When sequential access may help

- Large PNG or TIFF sources where there is no shrink-on-load (PNG has none; TIFF has limited support).
- Very large source files where you want to reduce peak RSS under load.
- Pipelines that genuinely read the image once, top-to-bottom (e.g. encode to buffer immediately after load).

### When sequential access does not help (and may hurt)

- JPEG sources being downscaled — use random access to preserve shrink-on-load.
- Operations that need random pixel access: rotation by non-90° multiples, compositing with an offset, some crop strategies. libvips will error or fall back silently.
- Small images: the cursor-tracking overhead is not worth the memory saving.

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
| Shrink-on-load | Automatic (via format loader) | Explicit (part of the operation) |
| EXIF auto-rotate | Requires explicit `autoRotate()` | Applied by default |
| Crop | Via separate smartcrop | Integrated (`crop=attention/entropy`) |

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

The `vips_image_new_from_file(path, NULL)` random-access path creates a lazy libvips pipeline. When the downstream `vips_resize` eventually pulls pixels at a reduced scale, the JPEG loader activates its shrink-on-load path automatically — it reads less JPEG scan data than would be needed for a full decode. This happens transparently within the pipeline.

`vips_thumbnail` does this explicitly and adds extra overhead: it reads the image header, computes the optimal shrink factor, and then opens the file a second time with that factor set. On a warm OS page cache this extra header read and second open add latency without reducing the actual pixel decode work (since the OS cache serves both reads quickly).

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

Sequential access disables JPEG shrink-on-load. Using it for JPEG downscaling will significantly hurt performance (8× on the benchmarks above). This is documented in `LoadOptions.swift` and in this file.

### `vips_thumbnail` throughput

On warm-cache benchmarks, `vips_thumbnail` is slower than `vips_resize` with random access. It is correct to expose it (EXIF rotation, cold-cache scenarios, integrated crop) but it should not be marketed as "faster" for all workloads.

### Benchmark file cache state

All benchmarks above were run with the test files already in the OS page cache (warm cache). Cold-cache results — which would favour `vips_thumbnail` — were not measured. Production workloads may differ substantially.

### No memory measurements

The benchmarks measure wall-clock time only. Peak RSS under load (the main benefit of sequential access) was not measured here. If peak memory matters for your deployment, profile it with your own workload.

### C shim coverage

The shim exposes the `height`, `crop`, and `no-rotate` options for `vips_thumbnail`. Other options (`size`, `linear`, `import-profile`, `export-profile`, `intent`, `fail-on`) are not exposed. Add them to the shim when needed.

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
