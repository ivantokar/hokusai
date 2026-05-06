# WebP Encoding Investigation

Motivated by a Reddit comment asking whether WebP conversion being ~8× slower than resize/rotate
is caused by libvips running libwebp single-threaded, or by some other knob.

---

## Test environment

| Field | Value |
|---|---|
| libvips | 8.18.2 |
| Platform | macOS (Apple Silicon, 12 logical cores) |
| Input | `2.webp` — 800×450 animated WebP, first frame loaded (sRGB, no alpha) |
| Tool | `hokusai benchmark webp` (added in this investigation) |
| Warmup | 3 runs per case |
| Iterations | 15 runs per case |

---

## 1. What the code does

WebP output flows through two paths depending on the call site:

| Path | C wrapper | Effort passed? |
|---|---|---|
| `toFile()` (`Convert.swift:49`) | `swift_vips_webpsave` | Yes (`options.effort ?? 4`) |
| `toBuffer()` (`Convert.swift:128`) | `swift_vips_webpsave_buffer` | **No** (effort was missing before this fix) |

The benchmark suite uses `toBuffer()`, so until the fix in this PR the effort value was always
libvips's compiled-in default (4). This was a latent bug: callers who set `SaveOptions.effort`
on a buffer encode were silently ignored.

**Fix applied:** `swift_vips_webpsave_buffer` now accepts and forwards the `effort` parameter.
Both `Convert.swift` and `VipsBackend.swift` updated accordingly.

---

## 2. libvips 8.18.2 WebP options (confirmed from `vips webpsave`)

Options that exist and are now accessible:

| Option | Range | Default | Notes |
|---|---|---|---|
| `Q` | 0–100 | 75 | Lossy quality |
| `lossless` | bool | false | Full lossless mode |
| `effort` | **0–6** | 4 | 0 = fastest, 6 = smallest file |
| `near-lossless` | bool | false | Lossless pre-processing with Q |
| `alpha-q` | 0–100 | 100 | Alpha-plane quality for lossy |
| `smart-subsample` | bool | false | High-quality chroma subsampling |
| `preset` | enum | default | picture / photo / drawing / icon / text |
| `min-size` | bool | false | Try to minimise output size |
| `mixed` | bool | false | Allow mixed lossy/lossless |
| `passes` | 1–10 | 1 | Entropy-analysis passes |

No thread-count option is exposed by `vips webpsave`. The libvips concurrency setting is
a separate global; see the concurrency sweep below.

---

## 3. Format comparison results

All cases: encode 800×450 sRGB image to in-memory buffer.

| Case | Mean | Median | P95 | Min | Max | Ops/s |
|---|---|---|---|---|---|---|
| `jpeg:q80` | 1.13 ms | 1.15 ms | 1.21 ms | 0.97 ms | 1.24 ms | 881 |
| `webp:q80:effort0` | 6.13 ms | 6.19 ms | 6.31 ms | 5.92 ms | 6.32 ms | 163 |
| `webp:q80:effort2` | 10.28 ms | 10.21 ms | 11.16 ms | 9.48 ms | 11.47 ms | 97 |
| `png:compression6` | 25.58 ms | 25.59 ms | 26.11 ms | 24.86 ms | 26.13 ms | 39 |
| `webp:q80:effort4` | 20.07 ms | 20.12 ms | 20.50 ms | 19.62 ms | 20.51 ms | 50 |
| `webp:q80:effort6` | 38.26 ms | 38.25 ms | 38.57 ms | 37.66 ms | 38.74 ms | 26 |
| `webp:lossless:effort4` | 172.58 ms | 172.41 ms | 175.47 ms | 169.99 ms | 175.68 ms | 6 |

Key observations:
- **JPEG is 18× faster** than WebP at the default effort (4). This is an encoder difference,
  not a libvips overhead: JPEG DCT encoding is a comparatively simple algorithm.
- **Effort is the dominant cost variable** for WebP lossy. Moving from effort 0 to effort 6
  increases encode time 6× (6 ms → 38 ms) while the output dimension and quality setting stay
  the same. The default effort=4 is a deliberate quality/speed trade-off.
- **Lossless WebP is ~8× slower** than lossy at the same effort. libwebp runs a substantially
  different (and more expensive) coding pass for lossless.
- PNG at compression=6 (zlib deflate) is in the same range as WebP effort=4 on this image.
  Both are slower than JPEG because they do more work per pixel for better compression.

---

## 4. Concurrency sweep (webp:q80:effort4)

libvips concurrency was set via `Hokusai.vipsConcurrency` before each group of iterations.
The same 800×450 encode was repeated at each setting.

| Concurrency | Mean | Median | P95 | Ops/s |
|---|---|---|---|---|
| 1 | 20.16 ms | 20.18 ms | 20.64 ms | 49.6 |
| 2 | 20.19 ms | 20.22 ms | 20.54 ms | 49.5 |
| 4 | 20.20 ms | 20.22 ms | 20.48 ms | 49.5 |
| 8 | 20.24 ms | 20.30 ms | 20.77 ms | 49.4 |
| 12 | 20.42 ms | 20.46 ms | 20.75 ms | 49.0 |

**Result: no measurable difference across concurrency 1–12.** The spread is within normal
run-to-run noise (< 0.3 ms).

This is the answer to the Reddit question: **the libvips concurrency knob does not affect
single-image WebP encode time.** libvips uses threads to parallelise its own image-pipeline
operations (e.g. tile-by-tile processing of large images), but the actual call into libwebp
to compress a fully-decoded pixel buffer is a single sequential operation per image. There is
no thread-count parameter in `vips_webpsave` / `vips_webpsave_buffer`.

---

## 5. Standard suite on the same input (for comparison)

| Case | Mean | P95 | Ops/s |
|---|---|---|---|
| `resize:1200x800` | 4.28 ms | 4.36 ms | 234 |
| `convert:webp:q80` | 20.02 ms | 20.51 ms | 50 |
| `rotate:33` | 3.23 ms | 3.52 ms | 309 |
| `text:stroke-shadow` | 34.54 ms | 35.88 ms | 29 |

`convert:webp:q80` corresponds to `webp:q80:effort4` in the matrix above — results agree.
Resize and rotate are pipeline operations that libvips executes tile-by-tile and *do* benefit
from its internal threading. WebP encoding is a serialised final step.

---

## 6. Answers

**Is WebP slower mainly because of encoding?**
Yes. The primary cost is the libwebp encoder itself, driven by the `effort` setting.
On this 800×450 image: effort=4 ≈ 20 ms, effort=0 ≈ 6 ms, effort=6 ≈ 38 ms.

**Does changing WebP effort significantly affect time?**
Yes — 6× range between effort=0 and effort=6. If throughput matters more than file size,
`effort: 0` yields the same quality target (q=80) in ~6 ms instead of ~20 ms.

**Does changing libvips concurrency affect WebP encoding time?**
No. Measured at concurrency 1, 2, 4, 8, 12 — all within noise at ~20 ms.

**Is there an explicit WebP thread-count knob through libvips?**
No. `vips webpsave` does not expose a thread-count option. The libvips concurrency setting
applies to libvips's own pipeline scheduler, not to the libwebp encode call.

**How does WebP compare with JPEG and PNG?**
On this image: JPEG q80 ≈ 1 ms, PNG compression=6 ≈ 25 ms, WebP q80 effort=4 ≈ 20 ms.
JPEG is far faster. PNG and WebP default effort are in the same order of magnitude.

---

## 7. Suggested reply to the Reddit comment

> We ran the benchmarks and inspected the code. The short answer: yes, a single WebP encode
> does not benefit from libvips concurrency. We measured webp:q80:effort4 at concurrency
> 1 through 12 and saw no difference (all within ~20 ms ± 0.3 ms on a 12-core machine,
> 800×450 image). libvips concurrency controls its own image-pipeline thread pool, but the
> final call into libwebp for a single image is sequential.
>
> The bigger lever is the `effort` parameter (0–6 in libvips 8.18.2, default 4).
> On our test input: effort=0 takes ~6 ms, effort=4 takes ~20 ms, effort=6 takes ~38 ms —
> a 6× spread at the same quality setting. If you need more throughput and can accept slightly
> larger files, `effort: 0` is the knob to reach for.
>
> For comparison: JPEG q80 on the same input takes ~1 ms — WebP encoding is inherently more
> compute-intensive per pixel. That gap exists regardless of concurrency settings.

---

## 8. Code changes in this investigation

| File | Change |
|---|---|
| `Sources/CVips/shim.h` | Added `effort` param to `swift_vips_webpsave_buffer`; added `swift_vips_concurrency_get/set` |
| `Sources/Hokusai/Operations/Convert.swift` | `toBuffer()` WebP path now forwards `options.effort` (was silently dropped) |
| `Sources/Hokusai/Backend/VipsBackend.swift` | Updated `toBuffer()` caller; added `concurrency` static property |
| `Sources/Hokusai/Hokusai.swift` | Exposed `vipsConcurrency` public property |
| `Sources/HokusaiCLI/main.swift` | Added `benchmark webp` subcommand with format matrix, effort sweep, concurrency sweep; suite now prints environment header |
