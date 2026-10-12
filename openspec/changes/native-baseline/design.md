## Context

SwiftPM `systemLibrary` targets resolve libvips and Cairo through pkg-config
but cannot express minimum versions, and distro packages vary widely (Ubuntu
24.04 ships libvips 8.15, Debian 13 ships 8.16.1). GitHub's macOS runner Xcode
releases lag swift.org toolchains.

## Decisions

- **Compile-time guards in the module headers.** `#error` on
  `VIPS_MAJOR_VERSION`/`VIPS_MINOR_VERSION` and `CAIRO_VERSION` is the only
  check that applies to every consumer build, not just CI. Rejected: a
  runtime check, which would let an incompatible build link and fail later.
- **Build libvips from release tarballs in Linux CI.** Exact pins
  (8.16.1 baseline, 8.18.x current) on any Swift container, cached per
  version/distro. Rejected: distro packages, which tie the libvips version to
  the Swift image's OS.
- **Baseline on `swift:6.0-jammy`.** Jammy's Cairo 1.16.0 makes the job test
  the actual Cairo minimum, not just libvips.
- **macOS Swift 6.4 via swiftly.** Installs the swift.org toolchain on the
  runner's newest Xcode SDK instead of waiting for a runner Xcode that bundles
  6.4.

## Risks / Trade-offs

- From-source libvips adds several minutes to a cold Linux job → cached by
  version and install-script hash.
- Consumers on older distros must build libvips themselves → documented in
  the README with a pointer to the CI install script.
