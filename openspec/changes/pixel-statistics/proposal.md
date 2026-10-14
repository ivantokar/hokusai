## Why

Hokusai could report what a source file said (`metadata()`, #43) but nothing
about the pixels of a pipeline, so callers had to encode and decode a result
just to measure it. #24 (roadmap #52, the additive slice) adds a
result-returning analysis terminal.

## What Changes

- New `Hokusai.stats()` returning `ImageStatistics`, evaluated over the
  **current immutable pipeline**, not the source.
- `ImageStatistics`: per-channel (`grey`, or `red/green/blue`, plus `alpha`)
  minimum and maximum with locations, sum, sum of squares, mean, and sample
  standard deviation; `isOpaque`; luminance `entropy` in bits; Laplacian
  `sharpness`; and a 16-level `dominantColor`.
- Measured on 8-bit pixels after conversion to sRGB or grey. The pipeline is
  evaluated into memory once and each measurement reads that copy, instead of
  re-running the pipeline per measurement.
- Runs on the evaluation scheduler, is registered for cancellation, and
  reports failures with the same typed errors as a terminal. It encodes
  nothing and does not consume the pipeline.

Not done: a public `histogram()` (optional in the issue and needs a typed
channel/bin model), alpha-weighted dominant colour, ICC-aware statistics.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `image-pipeline`: adds the pixel analysis requirement.

## Impact

- Public API: new `stats()`, `ImageStatistics`, `ChannelStatistics`.
- No existing behavior changes.
