## Why

Hokusai documents a libvips 8.9 minimum that has not been true since the
bridge started using `vips_addalpha` (libvips 8.16), and CI tests neither the
current Swift release nor any pinned native version. The next-major roadmap
(#52, Phase 0 / #49) needs one reproducible, tested build contract before the
evaluator migration starts.

## What Changes

- **BREAKING** Native baseline raised to libvips 8.16+ and Cairo 1.16+. The
  native bridge rejects older headers at compile time with a clear `#error`.
- Swift 6.0 remains the minimum toolchain; Swift 6.4 becomes a supported,
  CI-tested toolchain on Linux and macOS.
- Remove the redundant `StrictConcurrency` experimental flag; Swift tools 6.0
  already compiles in Swift 6 language mode with complete checking.
- `HokusaiNIO` depends explicitly on `NIOFoundationCompat` for `Data`
  conversions.
- CI matrix: Linux baseline (Swift 6.0, libvips 8.16.1 built from source,
  Cairo 1.16), Linux current (Swift 6.4, libvips 8.18.x with optional codecs),
  macOS current (Swift 6.4, Homebrew). Every job prints and asserts the
  versions it tested.
- README separates required native dependencies from build-dependent codec
  capabilities.

Deferred to later roadmap issues: moving Cairo code out of `CVips` (#44),
optional-capability reporting and security policy (#28), `hokusai info`
capability output (#48).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `native-runtime`: adds the supported toolchain/native baseline and its
  compile-time enforcement.

## Impact

- Public API: unchanged.
- CLI and output formats: unchanged.
- Build: consumers on libvips < 8.16 or Cairo < 1.16 (e.g. Ubuntu 24.04 or
  Debian 12 distro packages) now fail at compile time instead of at link time
  or with silently different behavior; they must install a newer libvips.
- Files: `Package.swift`, `Sources/CVips/shim.h`, `Sources/CCairo/cairo.h`,
  `Sources/HokusaiNIO/HokusaiNIO.swift`, `.github/workflows/ci.yml`,
  `.github/scripts/*`, `README.md`, `CHANGELOG.md`.
