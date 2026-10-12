## 1. Package and native bridge

- [x] 1.1 Remove the redundant `StrictConcurrency` experimental flag
- [x] 1.2 Add compile-time libvips >= 8.16 and Cairo >= 1.16 guards
- [x] 1.3 Depend on `NIOFoundationCompat` in `HokusaiNIO`

## 2. CI matrix

- [x] 2.1 Build pinned libvips releases from source in Linux CI
- [x] 2.2 Linux baseline job: Swift 6.0, libvips 8.16.1, Cairo 1.16
- [x] 2.3 Linux current job: Swift 6.4, libvips 8.18.x with optional codecs
- [x] 2.4 macOS current job: Swift 6.4 toolchain, Homebrew libvips
- [x] 2.5 Print and assert Swift/libvips/Cairo versions in every job

## 3. Documentation and verification

- [x] 3.1 README separates required dependencies from build-dependent codecs
- [x] 3.2 CHANGELOG records the breaking native baseline
- [x] 3.3 Verify the guard rejects libvips 8.15 headers
- [x] 3.4 Full test suite passes on Swift 6.4 (macOS) and Swift 6.0 + libvips 8.16.1 (Linux)
