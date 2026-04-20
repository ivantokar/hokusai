# Changelog

All notable changes to this project are documented in this file.

## [0.2.0] - 2026-04-20

### Changed
- Removed ImageMagick as a required dependency and moved to a libvips-only runtime/backend.
- Updated CI and release workflows to install only libvips + pkg-config.
- Updated README installation, architecture, and platform notes to describe libvips-only behavior.
- Added first-party `hokusai` CLI target and documented source/Homebrew installation paths.

### Compatibility
- Preserved public API shape for legacy `magickVersion` and `HokusaiError.magickError` as deprecated compatibility shims.
- No ImageMagick runtime/backend support remains.

## [0.1.2] - Previous

- Previous release.
