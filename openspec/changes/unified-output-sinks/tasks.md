## 1. Native lowering

- [x] 1.1 Target-based saver shims for JPEG, PNG, WebP, AVIF with every option and explicit AV1
- [x] 1.2 `NativeEncoder`: one mapping per format
- [x] 1.3 Memory sink with ownership transfer into `Data`
- [x] 1.4 Hokusai-owned file target: lazy open, errno capture, byte count, cleanup of partial regular files

## 2. Terminals

- [x] 2.1 `Evaluator.selectEncoder`: shared capability check and lowering
- [x] 2.2 Route `data()` and `write(to:)` through `NativeEncoder`; remove `legacySaveOptions`

## 3. Tests and docs

- [x] 3.1 Byte-identical memory/file output for every raster format
- [x] 3.2 Progressive JPEG, interlaced PNG, lossless WebP, real AV1 in both sinks
- [x] 3.3 Explicit encoder vs extension; metadata policy parity; capability gating
- [x] 3.4 `io(.write)`, no partial file on failure or cancellation, ENOSPC on Linux
- [x] 3.5 README output section, CHANGELOG
