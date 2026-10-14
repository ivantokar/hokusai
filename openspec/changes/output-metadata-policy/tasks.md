## 1. Policy

- [x] 1.1 `MetadataPolicy` with per-family actions and `.default`, `.preserveAll`, `.removeAll`
- [x] 1.2 Terminal configuration `metadataPolicy(_:)`; remove `preserveMetadata()` and `removeMetadata()`

## 2. Lowering

- [x] 2.1 Families to `VipsForeignKeep`; modern savers take `keep`, not `strip`
- [x] 2.2 Orientation: minimal EXIF when EXIF is removed, tag removal without rotation
- [x] 2.3 Density: stop carrying the source resolution, including EXIF resolution fields and the raw block
- [x] 2.4 One lowering shared by the memory and file sinks

## 3. CLI, tests, docs

- [x] 3.1 CLI default policy; `--strip-metadata` is `.removeAll`
- [x] 3.2 Per-family fixtures on JPEG, PNG, WebP, AVIF; keep-flag mapping; sink parity; pixels untouched
- [x] 3.3 README matrix and CHANGELOG
