## ADDED Requirements

### Requirement: Write PDF as a raster document

PDF output SHALL embed the evaluated raster pixels as an image on each page
and SHALL NOT claim vector text or document structure. Document properties
SHALL be written only when supplied, and nothing SHALL be copied from the
source's embedded metadata.

#### Scenario: Keep transparency

- **WHEN** a caller writes an RGBA image to PDF without a background
- **THEN** the image keeps a soft mask for its alpha

#### Scenario: Paint a background

- **WHEN** a caller supplies a background colour
- **THEN** the page is painted with it behind the image

### Requirement: Size pages without hidden resampling

The page SHALL be sized by `PDFPageSize`, in which only `.image(dpi:)` carries
a resolution. The raster SHALL be scaled uniformly to fit inside the margins and
placed by the anchor. The library SHALL NOT resample the raster because a page
has a physical size, and SHALL downsample only when `maxEffectiveDPI` is set and
exceeded.

#### Scenario: Resolve page geometry

- **WHEN** a caller selects `.image(dpi: 144)` for a 144 × 72 pixel raster
- **THEN** the page is 72 × 36 points
- **AND** A4 landscape is 841.89 × 595.276 points

#### Scenario: Cap the effective resolution

- **WHEN** a 320-pixel-wide raster is placed across 144 points and
  `maxEffectiveDPI` is 80
- **THEN** the embedded raster is 160 pixels wide
- **AND** without the option it stays 320 pixels wide

### Requirement: Share sink semantics for PDF output

`data()` and `write(to:)` SHALL use one PDF writer. A file SHALL be written
incrementally as bytes are produced and SHALL NOT first be built as `Data`. A
destination that cannot be opened or written SHALL fail with
`HokusaiError.io` for a write operation, decided from the system error code. A
failed or cancelled write SHALL remove the partial regular file, and a
cancellation SHALL throw `CancellationError`.

#### Scenario: Missing destination folder

- **WHEN** a caller writes a PDF into a folder that does not exist
- **THEN** the terminal throws `HokusaiError.io` with a write operation

#### Scenario: Cancelled write

- **WHEN** a running PDF `write(to:)` is cancelled
- **THEN** it throws `CancellationError` and leaves no file

### Requirement: Keep Cairo failures and capability separate

Cairo failures SHALL carry Cairo's own status text as the diagnostic and SHALL
NOT use libvips' error log. PDF output capability SHALL be independent of PDF
input capability.

#### Scenario: Independent capabilities

- **WHEN** a build can read PDFs but Cairo has no PDF surface
- **THEN** PDF output is reported unsupported
