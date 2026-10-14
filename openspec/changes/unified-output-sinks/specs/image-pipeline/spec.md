## ADDED Requirements

### Requirement: Encode identically for every sink

A selected raster encoder SHALL define the encoded format and codec options
independently of the destination. `data()` and `write(to:)` SHALL apply the
same options for JPEG, PNG, WebP, and AVIF, and SHALL produce identical bytes
for the same pipeline. AVIF output SHALL be AV1 in every sink. An explicit
encoder SHALL win over the destination's file extension. A missing encoder
capability SHALL fail with the same `unsupported` error for either sink before
any work starts.

#### Scenario: Progressive options reach both sinks

- **WHEN** a caller selects progressive JPEG or interlaced PNG
- **THEN** both the `data()` bytes and the written file are progressive or
  interlaced, and the two are identical

#### Scenario: AVIF is AV1 in memory and on disk

- **WHEN** a caller selects AVIF output
- **THEN** the encoded data from `data()` and from `write(to:)` carries the
  `avif` brand and AV1 codec configuration, not HEVC

#### Scenario: Explicit encoder overrides the extension

- **WHEN** a caller selects PNG and writes to a path ending in `.jpg`
- **THEN** the file contains PNG data

### Requirement: Report destination failures as I/O

A destination that cannot be opened or written SHALL fail with
`HokusaiError.io` for a write operation, carrying the system's reason, decided
from the system error code and not from libvips text. A pipeline that fails
before producing output SHALL NOT create or modify the destination, and a
regular file whose write fails after output began SHALL be removed rather than
left as a partial image.

#### Scenario: Missing destination folder

- **WHEN** a caller writes JPEG, PNG, or WebP into a folder that does not exist
- **THEN** the terminal throws `HokusaiError.io` with a write operation

#### Scenario: Source fails before output

- **WHEN** the source cannot be decoded and the caller writes to a new path
- **THEN** the terminal throws `HokusaiError.decode`
- **AND** no file exists at the path

#### Scenario: Cancelled write

- **WHEN** a running `write(to:)` is cancelled
- **THEN** it throws `CancellationError` and leaves no partial file
