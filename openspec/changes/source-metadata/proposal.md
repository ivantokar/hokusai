## Why

`metadata()` returned facts about whatever eager native graph existed at the
call site, mixed stored-source facts with transformed-image facts in one type,
reported every multi-page file as animated, read `sizeof_header` as the source
size, and derived the format by deleting `load` from the loader name (so AVIF
and HEIC were indistinguishable). After #34 a pipeline is a deferred plan, so
that meaning no longer exists. #43 (roadmap #52, Phase 2) defines it
deliberately.

## What Changes

- **BREAKING** `Hokusai.metadata()` is `async` and means "what the root source
  reported when opened". It lowers no operations and reads no pixels, runs on
  the evaluation scheduler, honours `InputOptions` (page, limits, access), and
  is cancelled with its task. A composite reports only its base source.
- **BREAKING** `ImageMetadata` is typed and curated: `ImageOrientation`
  (1...8) with `orientedSize`; `PixelMetadata` (channels, alpha,
  `PixelInterpretation`, `PixelSampleFormat`, bits per sample, palette); one
  `density` in DPI with an optional `ResolutionUnit`; `PageMetadata`;
  `AnimationMetadata` (loop count, frame delays) present only for real
  animation; `sourceByteSize`; `isProgressive`; `chromaSubsampling`; and raw
  owned `exif`, `iccProfile`, `xmp`, `iptc` blocks.
- Format comes from an explicit loader mapping; `heifload` splits into AVIF
  and HEIF by `heif-compression`; unknown loaders give `nil`.
- `HokusaiImage.metadata()` returns the same typed value with no source size;
  `extendedMetadata()` remains only on the legacy handle until #32.

Not done here: page ranges and full animation processing (#27); typed
ICC colour management; `ImageFormat` growth for JXL/JP2K (#23); `stats()`
(#24); a pipeline-inspection API (deliberately separate).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `image-pipeline`: the metadata requirement now defines source metadata.

## Impact

- Public API: `metadata()` becomes async; `ImageMetadata` changes shape (see
  CHANGELOG for the field-by-field mapping).
- CLI: `hokusai inspect` shows the typed fields.
- Output formats: unchanged.
