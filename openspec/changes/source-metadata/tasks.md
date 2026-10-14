## 1. Model and extraction

- [x] 1.1 `ImageMetadata` and typed sub-values (orientation, pixel, density, pages, animation)
- [x] 1.2 Native extraction with explicit format, interpretation, and sample mappings
- [x] 1.3 Raw owned EXIF, ICC, XMP, IPTC blocks

## 2. API

- [x] 2.1 Async `Hokusai.metadata()` through the evaluation scheduler; `Evaluator.inspect`
- [x] 2.2 Legacy handle returns the typed value; CLI `inspect` uses the typed fields

## 3. Tests and docs

- [x] 3.1 Fixtures: rich JPEG (EXIF/XMP/IPTC/ICC), animated GIF and WebP, AVIF, HEIC, CMYK, 16-bit and palette PNG, centimetre TIFF
- [x] 3.2 Source-only meaning, orientation (all eight), byte size, pages versus animation, format, density, blocks, errors, cancellation, concurrency
- [x] 3.3 README and CHANGELOG
