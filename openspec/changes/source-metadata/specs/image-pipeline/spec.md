## RENAMED Requirements

- FROM: `### Requirement: Expose pipeline metadata`
- TO: `### Requirement: Expose source metadata`

## MODIFIED Requirements

### Requirement: Expose source metadata

`metadata()` SHALL be asynchronous and SHALL report what the pipeline's root
source reported when it was opened, never properties of the transformed
pipeline. It SHALL read the source header without lowering operations or
decoding pixels, SHALL honour the source's `InputOptions`, SHALL describe only
the base source of a composite pipeline, and SHALL be cancelled with its task.
Stored width and height SHALL NOT be swapped for orientation. Multi-page
sources SHALL NOT be reported as animated, and animation SHALL require frame
delays. The format SHALL be identified from the loader and HEIF compression,
and SHALL be `nil` when it cannot be identified reliably. Pixel interpretation
SHALL be reported separately from any embedded ICC profile. Embedded EXIF, ICC,
XMP, and IPTC blocks SHALL be returned as owned raw data.

#### Scenario: Inspect decoded image metadata

- **WHEN** a caller requests metadata from a valid pipeline
- **THEN** the result describes the root source header without requiring an
  encoded output

#### Scenario: Transforms do not change source metadata

- **WHEN** a caller inspects a source and a pipeline derived from it with
  resize, blur, and auto-orient
- **THEN** both calls return equal metadata

#### Scenario: Orientation is typed and not applied

- **WHEN** a source carries EXIF orientation 6
- **THEN** its stored width and height are unswapped
- **AND** `orientedSize` has them swapped

#### Scenario: Multi-page is not animation

- **WHEN** a caller inspects a three-page TIFF
- **THEN** the page count is 3 and the source is not animated

#### Scenario: Distinguish AVIF from HEIC

- **WHEN** a caller inspects an AVIF file and a HEIC file
- **THEN** their formats are AVIF and HEIF respectively

#### Scenario: Report the source byte size

- **WHEN** a caller inspects `Data` or a local file
- **THEN** the byte size equals the data length or the file size
