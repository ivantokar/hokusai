## Decisions

### Metadata is source metadata

The immutable plan has a root source and deferred operations. Reporting
anything about the transformed image would require evaluating the plan, which
is what `OutputInfo` and a future `stats()` are for. `metadata()` therefore
opens the root source only and reads its header, which also lets it work
before any evaluation and without a slot-consuming lowering.

### Typed model over a string dictionary

libvips headers are stringly typed and loader-specific. Hokusai curates the
generally useful facts into closed value types and returns `nil` rather than a
guess when a loader does not report one. Enumerations of native values
(`PixelInterpretation`, `PixelSampleFormat`) carry an `unknown` case and are
documented as non-exhaustive.

### Explicit rules where libvips is ambiguous

- Format: exact loader-name mapping (the `_source`/`_buffer` suffixes are
  removed by suffix, not substring), with `heif-compression` deciding AVIF
  versus HEIF.
- Animation: only when the source carries a `delay` array. A page count alone
  never means animation.
- Density: libvips reports exactly 1 pixel/mm when a file recorded nothing, so
  that value is `nil`. A file that really records 25.4 DPI is indistinguishable
  and also reads as `nil`; the ambiguity is documented rather than guessed at.
- `isProgressive`: JPEG from `jpeg-multiscan`, PNG from `interlaced`; other
  formats `nil`. `isPalette`: PNG only.
- IPTC: libvips exposes the whole Photoshop image-resource block, so that is
  what `iptc` holds.

### Scheduling

Inspection runs through the evaluation scheduler like any terminal, so it is
admitted, bounded, and cancellable by the same rules. A separate lightweight
pool is left for a measured need.
