## 1. Options

- [x] 1.1 `InputOptions`: access, failOn (+ `.truncated`), page, limits, revalidate; remove `pages`
- [x] 1.2 `InputLimits` with centralised defaults and overflow-safe checks
- [x] 1.3 Remove `LoadOptions`; legacy loaders take `InputOptions`; remove `Hokusai(path:)`

## 2. Native loading

- [x] 2.1 Shims pass access, fail_on, page, revalidate to libvips
- [x] 2.2 Single-page selection from the reported page count
- [x] 2.3 Byte, pixel, and channel limits; resource kinds
- [x] 2.4 Source probe classifies pixel-time source failures as `decode`

## 3. Tests and docs

- [x] 3.1 failOn levels on truncated and bad-checksum fixtures; access; pages; limits; revalidate; ownership; concurrency
- [x] 3.2 Fix `pixel.png` checksum; add `corrupt-crc.png`, `truncated.jpg`, `multipage.tif`
- [x] 3.3 README input section, CHANGELOG
