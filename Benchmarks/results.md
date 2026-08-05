# Hokusai Pipeline Benchmarks

Measured on the environment in [environment.md](environment.md). Raw samples
and summary statistics are in [results.csv](results.csv).

These are full Hokusai public-API pipelines, not pre-decoded encoder-only
timings. Each row measures `load → WebP` against
`load → Gaussian blur(σ=50) → WebP`.

Run them again with:

```bash
hokusai benchmark pipeline \
  --input Benchmarks/file_example_JPG_1MB.jpg --sigma 50 --warmup 2 --iterations 5

hokusai benchmark pipeline \
  --input Benchmarks/file_example_WEBP_1500kB.webp --sigma 50 --warmup 2 --iterations 5
```

## Results

| Input | Pipeline | Mean | Median | P95 | Ops/s |
| --- | --- | ---: | ---: | ---: | ---: |
| JPEG, 3800 × 2534 | load → WebP | 349.05 ms | 348.16 ms | 354.70 ms | 2.86 |
| JPEG, 3800 × 2534 | load → blur(σ=50) → WebP | 362.74 ms | 361.90 ms | 368.48 ms | 2.76 |
| WebP, 5760 × 3840 | load → WebP | 828.69 ms | 829.94 ms | 831.62 ms | 1.21 |
| WebP, 5760 × 3840 | load → blur(σ=50) → WebP | 913.88 ms | 893.23 ms | 956.33 ms | 1.09 |

## What this shows

The σ=50 blur adds only 13.68 ms (3.9%) to the JPEG pipeline and 85.19 ms
(10.3%) to the larger WebP pipeline. WebP encoding remains the dominant cost;
the small incremental blur cost is consistent with libvips pipeline scheduling
around that final encoder stage.

These are measurements on one machine and two inputs, not universal performance
claims. The command accepts `--concurrency-sweep` for a separate experiment on
how global libvips concurrency affects the blur-to-WebP path.
