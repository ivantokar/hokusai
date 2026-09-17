# Legacy Image API Specification

## Purpose

Preserve the currently shipped libvips-backed image-handle API while consumers
migrate to the immutable `Hokusai` pipeline. This specification describes the
actual compatibility surface; new features should target `Hokusai(data:)` or
`Hokusai(url:)` unless compatibility is required.

## Requirements

### Requirement: Load legacy image handles synchronously

The library SHALL provide synchronous `Hokusai.image(from:)`,
`loadFromFile(_:)`, and `loadFromBuffer(_:)` entry points that return
`HokusaiImage`. File and byte-buffer inputs SHALL initialize libvips as needed.
Buffer-backed input SHALL copy its source bytes so callers may release or
mutate their original `Data` after loading.

#### Scenario: Release source bytes after loading

- **WHEN** a caller loads an image from `Data` and then releases or mutates
  that `Data`
- **THEN** the returned `HokusaiImage` remains decodable and encodable

### Requirement: Offer random and sequential loading modes

The legacy loading entry points SHALL accept `LoadOptions(access:)`. Random
access SHALL remain the default and safe choice for all operations. Sequential
access SHALL be a forward-only memory-reduction hint and may fail when a later
operation requests pixels outside its cached scanline window.

#### Scenario: Use default access mode

- **WHEN** a caller loads an image without `LoadOptions`
- **THEN** the library uses random access

#### Scenario: Request sequential loading

- **WHEN** a caller loads an image with `LoadOptions.sequential`
- **THEN** libvips receives a sequential access hint
- **AND** the caller remains responsible for using a compatible forward-only
  pipeline

### Requirement: Generate optimized legacy thumbnails

The static legacy thumbnail entry points SHALL support file-path and `Data`
sources with a requested width, optional height, crop strategy, and EXIF
auto-rotation control. For sources that support it, file and buffer entry
points SHALL use libvips shrink-on-load. A thumbnail from an already loaded
`HokusaiImage` SHALL use libvips thumbnail behavior without shrink-on-load.

#### Scenario: Create a width-only thumbnail

- **WHEN** a caller requests a thumbnail with only a positive width
- **THEN** the output width equals the requested width
- **AND** the height preserves the source aspect ratio

#### Scenario: Create a cropped thumbnail

- **WHEN** a caller supplies both bounds and an attention, entropy, or centre
  crop strategy
- **THEN** the output has the requested dimensions

#### Scenario: Respect EXIF orientation

- **WHEN** a caller creates a thumbnail from an EXIF-oriented image without
  setting `noRotate`
- **THEN** the output is auto-oriented before its dimensions are resolved

### Requirement: Retain synchronous legacy transforms and terminals

`HokusaiImage` SHALL retain its existing synchronous transformation,
metadata-inspection, `toBuffer`, and `toFile` APIs for compatibility. These
operations SHALL return a new handle for transformations and SHALL preserve the
native ownership and lifecycle guarantees of the runtime.

#### Scenario: Transform a loaded handle

- **WHEN** a caller resizes or thumbnails a `HokusaiImage`
- **THEN** the operation returns a new image handle
- **AND** the input handle remains usable
