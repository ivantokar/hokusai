## 1. Bridge and model

- [x] 1.1 Move Cairo into `CCairo` as a libvips-free bridge with a write callback
- [x] 1.2 New `PDFPageSize`, `PDFOptions`, margins, metadata, `OutputInfo.pdf`
- [x] 1.3 Pure page layout with validation

## 2. Output

- [x] 2.1 `PDFOutputSink` for memory (ownership transfer) and file (errno, cleanup, cancellation)
- [x] 2.2 One-buffer raster: libvips to RGBA once, premultiplied in place
- [x] 2.3 Multi-page-capable `PDFDocumentWriter`
- [x] 2.4 `maxEffectiveDPI` downsampling
- [x] 2.5 Route both terminals through the writer

## 3. Tests and docs

- [x] 3.1 Geometry, validation, premultiplication, stride, alpha, caps
- [x] 3.2 Sink parity, I/O and cancellation failures, independent capabilities, two pages via an independent reader
- [x] 3.3 Peak memory measured against the previous path
- [x] 3.4 README and CHANGELOG
