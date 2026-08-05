# Benchmark Environment

The current results in `results.md` and `results.csv` were measured with the
fixtures committed beside this file. They replace the earlier v0.3.0 figures,
whose generated input set is no longer present in the repository.

| Property | Value |
| --- | --- |
| Hokusai commit | `f14f2c7` |
| Build configuration | Release (`swift run -c release`) |
| Swift | 6.3.3 |
| libvips | 8.18.2 |
| OS | macOS 27.0 (26A5388g) |
| `vips_concurrency` | 12 (libvips default) |

## Fixtures

| Fixture | Properties |
| --- | --- |
| `file_example_JPG_1MB.jpg` | 3800 × 2534, 3-channel sRGB progressive JPEG, 1.0 MB |
| `file_example_WEBP_1500kB.webp` | 5760 × 3840, 3-channel sRGB WebP, 1.4 MB |

## Method

- Warm up each path twice, then measure five complete pipeline evaluations.
- Each evaluation creates a fresh Hokusai pipeline: source decode → optional
  `blur(sigma: 50)` → WebP Q80 at effort 4 → in-memory output.
- `data()` forces the entire libvips pipeline to evaluate. Disk writes are not
  included.
- The small sample count is intentional for this first reproducible run; use
  `--iterations 20` or more when comparing changes across machines.
