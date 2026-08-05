# Hokusai v0.3.0 Benchmarks

Measured on the environment described in [environment.md](environment.md)
(Apple M4 Pro, 12 cores, libvips 8.18.2, libwebp 1.6.0, release build,
commit `cbb2e68`). Raw data: [results.csv](results.csv). Every produced image
was validated (WebP magic, decodable, exact expected dimensions); all cases
passed. Warm-up runs preceded every measurement; no single-run numbers.

### Environment

| Property | Value |
|----------|-------|
| Hokusai | `cbb2e68` (v0.3.0), release build |
| Swift / libvips / libwebp | 6.3.3 / 8.18.2 / 1.6.0 |
| Hardware | Apple M4 Pro, 12 logical cores, 24 GB RAM, macOS 27.0 |
| Default `vips_concurrency` | 12 |

---

## Benchmark 1 — Plain WebP encode vs `vips_concurrency`

6000×4000 JPEG decoded once, then encoded to WebP Q80 repeatedly
(encode-only cost; n=8 per row).

### WebP encode

| Concurrency | Mean | P95 | Ops/sec |
|------------:|-----:|----:|--------:|
| 1  | 1219.6 ms | 1231.4 ms | 0.82 |
| 2  | 1232.7 ms | 1272.4 ms | 0.81 |
| 4  | 1230.5 ms | 1252.7 ms | 0.81 |
| 12 | 1231.7 ms | 1276.8 ms | 0.81 |

CPU utilisation was ~100% of **one** core in every row (user CPU ≈ 1201–1209 ms
per op, flat). **`vips_concurrency` does not improve a plain WebP encode at
all** — libwebp encodes a single image on a single thread, and no amount of
libvips threading changes that.

---

## Benchmark 2 — JPEG → resize(1200 px) → WebP by access mode

6000×4000 JPEG → 1200×800 WebP Q80. Full pipeline per iteration, libvips
operation cache disabled (n=10).

### Resize + WebP

| Mode | Mean | P95 | Ops/sec |
|------|-----:|----:|--------:|
| random (default) | 136.1 ms | 138.3 ms | 7.35 |
| sequential | 151.8 ms | 154.5 ms | 6.59 |
| thumbnail() | **125.1 ms** | 144.6 ms | **7.99** |

- `thumbnail()` is fastest and uses the least CPU (user 125 ms/op vs 192 ms/op
  for random): JPEG shrink-on-load decodes at 1/2 scale before resampling.
- Sequential is only **11% slower** than random here — not the "8×" that a
  warm-operation-cache benchmark suggests (see Benchmark 5 for that artifact).
- EXIF bonus row: the same pipeline on an EXIF Orientation=6 source produced a
  correctly auto-rotated 1200×1800 via `thumbnail()` (141.4 ms) while plain
  resize left the pixels un-rotated — dimension validation caught the
  difference by design.

PNG comparison (4000×4000 RGBA → 1200×1200, n=6):

| Mode | Mean | P95 | Ops/sec |
|------|-----:|----:|--------:|
| random | **359.2 ms** | 361.8 ms | **2.78** |
| sequential | 374.9 ms | 381.1 ms | 2.67 |
| thumbnail() | 474.9 ms | 479.0 ms | 2.11 |

**PNG has no shrink-on-load**, so `thumbnail()` is 32% *slower* than plain
resize there (it pays for header probing and a second open with no decode
savings).

---

## Benchmark 3 — JPEG → gaussian blur(σ=5) → WebP vs `vips_concurrency`

24 MP pipeline, cache disabled, n=6. (Blur is not public Hokusai API yet;
this calls the same libvips functions the shim wraps.)

| Concurrency | Wall mean | User CPU/op | Sys CPU/op | CPU util |
|------------:|----------:|------------:|-----------:|---------:|
| 1  | 1030.2 ms | 1004.6 ms | 22.9 ms | 100% |
| 2  | 964.7 ms  | 1004.8 ms | 26.5 ms | 107% |
| 4  | 918.2 ms  | 1000.8 ms | 23.6 ms | 112% |
| 12 | 908.4 ms  | 1036.9 ms | 28.5 ms | 117% |

Answer to the question: **total CPU stays roughly constant (~1005–1037 ms) while
wall time drops only 12%.** The blur stage itself parallelises, but the serial
WebP encode (~850 ms of the pipeline) dominates, so extra threads have little
to chew on. There is no CPU blow-up — just limited benefit.

---

## Benchmark 4 — JPEG → resize(1200) → blur(σ=5) → WebP

Same pipeline with the resize first, so all stages operate on small pixels
(n=10).

| Concurrency | Wall mean | Ops/sec | User CPU/op | CPU util |
|------------:|----------:|--------:|------------:|---------:|
| 1  | 184.6 ms | 5.42 | 176.1 ms | 99% |
| 2  | 147.1 ms | 6.80 | 173.8 ms | 122% |
| 4  | 132.1 ms | 7.57 | 175.7 ms | 137% |
| 12 | **129.0 ms** | **7.75** | 197.0 ms | 160% |

Here decode+resize+blur are a bigger share of the pipeline, so threading buys a
real **30% latency win** from 1→12, at slightly higher total CPU. Throughput per
op improves accordingly.

---

## Benchmark 5 — load→resize→encode vs thumbnail→encode (warm vs unique)

Two workloads:
- **warm cache** — the same file every iteration, libvips operation cache at
  its default (100 ops), n=20. Sources: 6000×4000 (300/1200 px),
  4000×6000 (1200×800 centre-crop).
- **unique images** — one pass over 50 distinct 3000×2000 JPEGs, cache at
  default but useless because every file is new.

### Thumbnail comparison — warm cache (same file repeatedly)

| Pipeline | Mean | P95 | Ops/sec |
|----------|-----:|----:|--------:|
| resize → 300 px | **9.0 ms** | 9.8 ms | 110.96 |
| thumbnail → 300 px | 61.9 ms | 64.3 ms | 16.15 |
| resize → 1200 px | **58.7 ms** | 60.8 ms | 17.02 |
| thumbnail → 1200 px | 119.8 ms | 120.5 ms | 8.35 |
| resize → 1200×800 crop | **51.9 ms** | 53.3 ms | 19.26 |
| thumbnail → 1200×800 crop | 151.9 ms | 159.7 ms | 6.59 |

### Thumbnail comparison — unique images (50 distinct files)

| Pipeline | Mean | P95 | Ops/sec |
|----------|-----:|----:|--------:|
| resize → 300 px | 22.4 ms | 23.4 ms | 44.65 |
| thumbnail → 300 px | **16.7 ms** | 17.8 ms | **59.78** |
| resize → 1200 px | **65.7 ms** | 69.4 ms | 15.23 |
| thumbnail → 1200 px | 69.6 ms | 71.9 ms | 14.37 |
| resize → 1200×800 crop | **65.2 ms** | 66.7 ms | 15.35 |
| thumbnail → 1200×800 crop | 70.5 ms | 73.8 ms | 14.18 |

**Why the flip:** in the warm case the libvips *operation cache* serves the
cached decode **and** the cached resize — the 9 ms "resize" row is really just
a WebP encode. `vips_thumbnail` is deliberately uncached in libvips (it
re-opens its source), so it cannot benefit. With unique files — the realistic
server workload — the cache is useless and `thumbnail()` wins wherever
shrink-on-load removes real decode work: **1.34× faster at 300 px (8×
downscale)**, and a wash at 1200 px, where the WebP encode dominates the
pipeline and the JPEG decoder can only shrink 2×. (The unique-crop rows
degenerate to plain resize because the 3000×2000 sources already have the
target 3:2 aspect.) Repeated same-file benchmarks flatter the resize path;
never extrapolate them to unique-file traffic.

---

## Benchmark 6 — Sequential vs Random (latency, throughput, peak RSS)

Pipelines from Benchmark 2; peak RSS from dedicated processes under
`/usr/bin/time -l` (6 iterations each, cache disabled).

### Sequential vs Random

| Mode | Mean | Peak RSS |
|------|-----:|---------:|
| JPEG 24 MP → 1200: random | 136.1 ms | 168.8 MB |
| JPEG 24 MP → 1200: sequential | 151.8 ms | 158.8 MB |
| JPEG 24 MP → 1200: thumbnail() | **125.1 ms** | **83.6 MB** |
| JPEG 24 MP → WebP full-size (random, no resize) | 1231.7 ms (encode stage) | 310.4 MB |
| PNG 16 MP → 1200: random | **359.2 ms** | 235.7 MB |
| PNG 16 MP → 1200: sequential | 374.9 ms | **193.7 MB** |
| PNG 16 MP → 1200: thumbnail() | 474.9 ms | 242.1 MB |

- Sequential saves memory, but modestly: −6% RSS for JPEG, −18% for PNG, at a
  10–11% latency cost.
- For JPEG the real memory win is `thumbnail()`: **half the RSS of random and
  sequential alike** (shrink-on-load decodes a fraction of the pixels), *and*
  it is the fastest.

---

## Benchmark 7 — Concurrent throughput

50 distinct 3000×2000 JPEGs → 1200×800 WebP Q80, N parallel workers
(Swift task group), `vips_concurrency` at its default of 12.

### Concurrent throughput

| Images | Concurrency | Images/sec |
|-------:|------------:|-----------:|
| 50 | 1 | 15.63 |
| 50 | 2 | 30.30 |
| 50 | 4 | 56.81 |
| 50 | 8 | **100.22** |

Per-image latency and CPU:

| Workers | Mean latency | P95 | CPU util (of 1200%) |
|--------:|-------------:|----:|--------------------:|
| 1 | 64.0 ms | 66.6 ms | 121% |
| 2 | 65.4 ms | 79.5 ms | 236% |
| 4 | 67.2 ms | 74.3 ms | 457% |
| 8 | 75.3 ms | 95.4 ms | 870% |

Throughput scales almost linearly with workers (6.4× at 8 workers) while
per-image latency rises only 18%. A single conversion only occupies ~1.2 cores
even with `vips_concurrency=12` — the pipeline's serial stages (JPEG decode,
WebP encode) cap what libvips threading can extract from one image.
**Image-level parallelism, not `vips_concurrency`, is how you use a multicore
machine.**

---

## Benchmark 8 — Peak RSS by strategy (`/usr/bin/time -l`)

| Scenario (6 iterations, 24 MP JPEG unless noted) | Peak RSS |
|--------------------------------------------------|---------:|
| random, full-size re-encode | 310.4 MB |
| random, resize → 1200 | 168.8 MB |
| sequential, resize → 1200 | 158.8 MB |
| thumbnail → 1200 | **83.6 MB** |
| PNG random, resize → 1200 | 235.7 MB |
| PNG sequential, resize → 1200 | 193.7 MB |
| PNG thumbnail → 1200 | 242.1 MB |

---

## Conclusions

1. **Does `vips_concurrency` improve plain WebP encoding?** No. 1220 ms at
   concurrency 1 and 1232 ms at 12, pegged at one core throughout — the
   libwebp encoder is single-threaded per image. It helps only pipelines with
   parallelisable pixel stages (blur: −12%, resize+blur: −30% wall time).
2. **Does it improve multi-image throughput?** No — throughput comes from
   running images in parallel: 15.6 → 100.2 images/sec going from 1 to 8
   workers with `vips_concurrency` fixed at 12. A single conversion uses only
   ~1.2 cores regardless of the setting.
3. **When should `thumbnail()` be preferred?** For formats with shrink-on-load
   (JPEG, WebP, TIFF pyramids, HEIF) whenever the target is much smaller than
   the source, and whenever EXIF auto-rotation matters: on unique files it was
   1.34× faster at 300 px and cut peak memory in half (83.6 vs 168.8 MB) at
   1200 px. Prefer plain `resize` for PNG (thumbnail is ~32% slower there) and
   for repeated re-processing of the same file, where the operation cache makes
   resize nearly free.
4. **When should sequential access be used?** Only when peak memory is the
   constraint in a genuinely single-pass pipeline and `thumbnail()` is not
   applicable (e.g. PNG): it saved 6% (JPEG) / 18% (PNG) RSS for a ~10%
   latency penalty. It is *not* 8× slower as warm-cache comparisons suggest —
   that figure was an operation-cache artifact. For JPEG downscaling,
   `thumbnail()` beats sequential on both speed and memory simultaneously.
5. **What should Hokusai recommend as defaults?** Keep `vips_concurrency` at
   its default (it never hurt and helps blur/resize-heavy pipelines); scale
   servers with concurrent image tasks (≈ up to core count, watching the +18%
   per-image latency at 8 workers); use `thumbnail()` for JPEG/WebP/HEIF
   thumbnail generation; use `resize` for PNG and kernel-controlled work;
   treat sequential access as a niche memory tool, not a performance one.
