# Benchmark Environment

All numbers in `results.md` / `results.csv` were measured on this machine and build.

### Environment

| Property | Value |
|----------|-------|
| Hokusai commit | `cbb2e68` (v0.3.0, `main`, clean tree) |
| Build configuration | Release (`swift build -c release`) |
| Swift | 6.3.3 (swiftlang-6.3.3.1.3, arm64-apple-macosx) |
| libvips | 8.18.2 (Homebrew) |
| libwebp | 1.6.0 |
| OS | macOS 27.0 (build 26A5378j) |
| CPU | Apple M4 Pro |
| RAM | 24 GB |
| Logical cores | 12 |
| Default `vips_concurrency` | 12 |
| Default libvips operation cache | 100 operations |

### Test images

All content derives from a real photograph (tiled + mild gaussian noise), so
JPEG/WebP entropy is photo-like, not synthetic-flat.

| Fixture | Properties |
|---------|-----------|
| `6000x4000.jpg` | 24 MP JPEG, Q90, 6.7 MB |
| `4000x6000.jpg` | 24 MP portrait JPEG, Q90, 6.8 MB |
| `4000x4000-alpha.png` | 16 MP RGBA PNG, 45 MB |
| `exif-rotated.jpg` | 3000×2000 JPEG with EXIF Orientation=6 (displays 2000×3000) |
| `many/` | 50 distinct 3000×2000 JPEGs, Q88, ~57 MB total |

### Methodology

- Release builds only; every case warmed up before measurement; ≥6–50 measured
  iterations per case (see `n` column in the CSV). No single-run numbers.
- Wall time via monotonic clock; user/system CPU via `getrusage(RUSAGE_SELF)`
  deltas over the measured window; peak RSS via `/usr/bin/time -l`
  (dedicated process per scenario).
- The libvips **operation cache** is disabled (`vips_cache_set_max(0)`) for all
  per-op pipeline benchmarks so numbers reflect real work, **except**
  benchmark 5's "warm cache" cases, which deliberately keep the default cache
  to demonstrate its effect. OS page cache is warm everywhere (files recently
  written); cold-storage I/O is out of scope.
- Every produced image was validated: WebP RIFF magic, decodable by libvips,
  exact expected dimensions (EXIF-rotated expectations account for
  auto-rotation). Encoding to a buffer forces full pipeline evaluation —
  no lazy-pipeline-creation-only timings.
- Gaussian blur is not part of Hokusai's public API yet; benchmarks 3–4 call
  the same libvips functions (`vips_gaussblur`, `vips_webpsave_buffer`) the
  Hokusai shim wraps, in-process, with identical settings.
- WebP output is Q80, default effort, in-memory buffers (no disk writes in the
  measured path).
