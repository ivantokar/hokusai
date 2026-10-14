## ADDED Requirements

### Requirement: Open encoded sources under one input policy

The library SHALL create a pipeline from encoded `Data` or a local file `URL`
under one `InputOptions` policy. Construction SHALL record the source without
opening or decoding it. It SHALL reject non-file URLs, empty data, and invalid
options with a typed `HokusaiError`. Decode failures and missing files SHALL
be reported as typed errors by the terminal method that first evaluates the
pipeline.

#### Scenario: Decode bytes into a pipeline

- **WHEN** a caller creates `Hokusai(data:)` with valid encoded image bytes
- **THEN** the caller receives a usable pipeline
- **AND** no output bytes are encoded until an output terminal is called

#### Scenario: Report invalid image bytes at evaluation

- **WHEN** a caller creates `Hokusai(data:)` from bytes that are not an image
  and configures transformations and an encoder
- **THEN** construction and configuration succeed
- **AND** `data()` throws `HokusaiError.decode`

#### Scenario: Reject a remote URL

- **WHEN** a caller creates `Hokusai(url:)` with a non-file URL
- **THEN** the initializer throws `HokusaiError.invalidInput`

#### Scenario: Reject an invalid option

- **WHEN** a caller supplies a negative page or a non-positive limit
- **THEN** construction throws `HokusaiError.invalidOption` naming the field

### Requirement: Apply the decoder policy and select one page

`InputOptions.failOn` SHALL be passed to the decoder, with `.warning` as the
default. A source rejected by that policy SHALL fail with
`HokusaiError.decode` naming the source, including failures that only appear
while pixels are read. `InputOptions.page` SHALL select exactly one
zero-based page; an out-of-range page SHALL fail with `invalidOption`, and a
non-zero page of a single-page format SHALL fail with `unsupported`.

#### Scenario: Apply the decoder failure policy

- **WHEN** a caller evaluates a truncated JPEG with `failOn: .none`
- **THEN** evaluation succeeds
- **AND** with `.truncated`, `.error`, or `.warning` it throws
  `HokusaiError.decode` naming the source

#### Scenario: Select one page

- **WHEN** a caller supplies `InputOptions(page: 2)` for a three-page TIFF
- **THEN** the pipeline contains only the third page

#### Scenario: Reject an out-of-range page

- **WHEN** a caller selects a page at or beyond the page count
- **THEN** the terminal throws `HokusaiError.invalidOption` naming `page`

### Requirement: Enforce input limits

The library SHALL reject inputs beyond `InputLimits` with
`HokusaiError.resource`. `maxBytes` SHALL be checked before `Data` is copied
into native storage and against a file's size; `maxPixels` and `maxChannels`
SHALL be checked from the image header before pixels are evaluated, with
overflow-safe pixel arithmetic.

#### Scenario: Reject oversized data before copying

- **WHEN** `Data` larger than `maxBytes` is supplied
- **THEN** construction throws `HokusaiError.resource` of kind `encodedBytes`
  reporting the limit and the actual size

#### Scenario: Reject too many pixels or channels

- **WHEN** a header reports more than `maxPixels` pixels or `maxChannels`
  bands
- **THEN** the terminal throws `HokusaiError.resource` of the matching kind
  before any pixels are decoded

#### Scenario: Reject an overflowing pixel count

- **WHEN** header dimensions multiply beyond the integer range
- **THEN** the input is rejected as exceeding `maxPixels`

## REMOVED Requirements

### Requirement: Accept supported image inputs

**Reason**: `InputOptions` is now applied rather than rejected, so the
"unsupported decoder option" behavior no longer exists; the requirement is
replaced by "Open encoded sources under one input policy".

**Migration**: Pass decoder policy, page selection, and limits through
`InputOptions`. Callers that relied on non-default values throwing
`unsupported` should expect them to take effect.
