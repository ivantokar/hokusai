## Why

PDF output materialised the whole document as `Data` before writing a file,
held two full rasters while converting, copied the encoded bytes three times,
reported Cairo failures through libvips' global error log, and offered a
`dpi` option that only applied to one page size. #44 (roadmap #52, Phase 2)
makes PDF a deliberate raster-document terminal that shares the sink and error
semantics of the other formats.

## What Changes

- **BREAKING** `PDFPageSize` is `.image(dpi:)`, `.a4(_:)`, `.letter(_:)`,
  `.points(width:height:)`; the global `dpi` argument is removed.
- `PDFOptions` adds margins, anchor, background, `maxEffectiveDPI`, and document
  metadata. Layout stays aspect-fit, centred by default; transparency is kept
  unless a background is given.
- Output goes through a Swift `PDFOutputSink` fed by Cairo's stream callback:
  memory accumulates in one buffer handed to `Data` without a copy, and files
  are written incrementally. File failures are `io(.write)` from the system
  error code; cancellation stops the sink; a failed write removes the partial
  regular file.
- One full raster: libvips produces 8-bit sRGB RGBA once and it is
  premultiplied in place into Cairo's layout; stride comes from
  `cairo_format_stride_for_width`.
- The Cairo bridge moves from `CVips/shim.h` into `CCairo`, with no libvips
  types, and reports Cairo statuses (never `vips_error`).
- `PDFDocumentWriter` can emit several pages; the terminal writes one.
- `OutputInfo.pdf` reports page count and first-page size in points.

Not done: strip/tile rendering and compressed-source embedding (both
benchmark-gated in the issue), ICC colour management, and mapping multi-page
pipelines to pages (#27).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `image-pipeline`: PDF output requirement.

## Impact

- Public API: `PDFPageSize` and `PDFOptions` reshaped; `pdf(...)` parameters
  change; `OutputInfo.pdf` added.
- Behavior: transparency is preserved; peak memory is one raster lower.
