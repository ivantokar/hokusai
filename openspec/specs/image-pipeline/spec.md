# Image Pipeline Specification

## Purpose

Define Hokusai's primary Swift image-processing API: a composable, immutable
pipeline backed by libvips that evaluates only at an explicit output terminal.

## Requirements

### Requirement: Accept supported image inputs

The library SHALL create a pipeline from encoded `Data` or a local file `URL`.
It SHALL reject non-file URLs and invalid input options with a typed
`HokusaiError`. The deprecated path-string initializer SHALL preserve its
behavior by forwarding to the file-URL initializer.

`InputOptions` SHALL accept its default values. Non-default decoder warning
policies and page-selection values are not implemented and SHALL fail
explicitly as unsupported rather than being silently ignored.

#### Scenario: Decode bytes into a pipeline

- **WHEN** a caller creates `Hokusai(data:)` with valid encoded image bytes
- **THEN** the caller receives a usable pipeline
- **AND** no output bytes are encoded until an output terminal is called

#### Scenario: Reject a remote URL

- **WHEN** a caller creates `Hokusai(url:)` with a non-file URL
- **THEN** the initializer throws `HokusaiError.invalidInput`

#### Scenario: Request an unsupported decoder option

- **WHEN** a caller supplies a non-default `InputOptions` value
- **THEN** construction throws `HokusaiError.unsupported`

### Requirement: Compose immutable transformations

The library SHALL expose chainable transformations for orientation, resize,
rotate, mirror, extract, extend, trim, blur, sharpen, colour conversion,
alpha handling, compositing, text, and metadata policy. Each transformation
SHALL return a new pipeline and SHALL leave its input pipeline usable for a
separate branch.

#### Scenario: Branch a base pipeline

- **WHEN** a caller derives two pipelines with different transformations from
  one base pipeline
- **THEN** both derived pipelines can be evaluated independently
- **AND** the base pipeline remains unchanged

#### Scenario: Validate dimensions before native work

- **WHEN** a caller requests a resize or extract with a non-positive dimension
- **THEN** the operation throws a typed validation error

### Requirement: Produce typed asynchronous outputs

The library SHALL provide asynchronous `data()` and `write(to:)` terminals.
They SHALL return encoded output with dimensions, format, and byte-size
metadata. Terminal evaluation SHALL not occupy Swift's cooperative executor.

#### Scenario: Encode an explicitly selected format

- **WHEN** a caller selects JPEG, PNG, WebP, AVIF, or PDF and calls `data()`
- **THEN** the returned `Output` contains bytes and `OutputInfo` for that
  format

#### Scenario: Infer output format from destination

- **WHEN** no encoder is selected and a caller calls `write(to:)` with a
  supported file extension
- **THEN** the library writes the file using that inferred format

### Requirement: Support raster and PDF encoding options

The pipeline SHALL validate output options before encoding. JPEG, PNG, WebP,
and AVIF SHALL accept their documented quality, compression, effort, lossless,
and progressive options. PDF output SHALL create a single-page Cairo-backed
raster document and validate page geometry and DPI. PDF output SHALL contain
the evaluated raster pipeline and SHALL NOT promise selectable vector text.

#### Scenario: Produce a PDF document

- **WHEN** a caller selects PDF output with a valid page size and DPI
- **THEN** the returned data begins with the PDF signature
- **AND** the output metadata identifies PDF format

#### Scenario: Reject invalid encoding options

- **WHEN** a caller supplies an out-of-range quality or non-positive PDF DPI
- **THEN** selection throws a typed validation error before output evaluation

### Requirement: Expose pipeline metadata

The library SHALL expose decoded header metadata, including dimensions,
channels, alpha presence, format when detectable, colour space, orientation,
density, pages, and available EXIF, ICC, and XMP data.

#### Scenario: Inspect decoded image metadata

- **WHEN** a caller requests metadata from a valid pipeline
- **THEN** the result describes the source image header without requiring an
  encoded output
