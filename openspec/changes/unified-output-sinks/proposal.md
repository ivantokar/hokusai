## Why

Modern output converted `OutputFormat` to legacy `SaveOptions` and then used
different C shims for memory and file output. The shims forwarded different
options: JPEG and PNG buffers ignored `progressive`, so one configuration
encoded differently depending on the destination, and an AVIF buffer had to
rely on a filename it did not have to pick AV1. #40 (roadmap #52, Phase 2)
makes the sink irrelevant to encoder semantics.

## What Changes

- `NativeEncoder`: one lowering per raster format (JPEG, PNG, WebP, AVIF) that
  calls the matching `*_save_target`. Memory and file output differ only in the
  `VipsTarget` passed in, so an option cannot reach one sink and miss the other.
  AVIF requests AV1 explicitly.
- Memory sink: a memory target whose encoded buffer transfers to `Data`
  without a copy and is released once.
- File sink: a Hokusai-owned target that writes with POSIX calls and records
  the first `errno`. The file opens on the first write, a failure after output
  began removes the regular file, and a write failure is
  `HokusaiError.io(.write)` decided from the error code, never from libvips
  text.
- `Evaluator.selectEncoder` checks capabilities and lowers the encoder once for
  both terminals, so an unavailable encoder is the same `unsupported` error for
  either sink.
- Remove `OutputFormat.legacySaveOptions`; modern output no longer touches
  `SaveOptions`. The legacy `HokusaiImage` API keeps its own path until #32.
- `OutputInfo.size` for `write(to:)` is the byte count written.

PDF keeps its in-memory path until #44. No public streaming API is added; the
target layer is what #46 builds on.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `image-pipeline`: adds sink-parity and destination-failure requirements.

## Impact

- Public API: unchanged.
- Behavior: `data()` now honours `progressive` for JPEG and PNG, matching the
  file output; failed file writes report `io(.write)` and leave no partial
  file; `write(to:)` size is the written byte count.
- Output formats: bytes for non-progressive configurations are unchanged.
