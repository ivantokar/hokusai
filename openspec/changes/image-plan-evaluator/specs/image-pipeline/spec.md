## MODIFIED Requirements

### Requirement: Accept supported image inputs

The library SHALL create a pipeline from encoded `Data` or a local file `URL`.
Construction SHALL record the source without opening or decoding it. It SHALL
reject non-file URLs, empty data, and invalid input options with a typed
`HokusaiError`. Decode failures and missing files SHALL be reported as typed
errors by the terminal method that first evaluates the pipeline. The
deprecated path-string initializer SHALL preserve its behavior by forwarding
to the file-URL initializer.

`InputOptions` SHALL accept its default values. Non-default decoder warning
policies and page-selection values are not implemented and SHALL fail
explicitly as unsupported rather than being silently ignored.

#### Scenario: Decode bytes into a pipeline

- **WHEN** a caller creates `Hokusai(data:)` with valid encoded image bytes
- **THEN** the caller receives a usable pipeline
- **AND** no output bytes are encoded until an output terminal is called

#### Scenario: Report invalid image bytes at evaluation

- **WHEN** a caller creates `Hokusai(data:)` from bytes that are not an image
  and configures transformations and an encoder
- **THEN** construction and configuration succeed
- **AND** `data()` throws `HokusaiError.decode`

#### Scenario: Report a missing file at evaluation

- **WHEN** a caller creates `Hokusai(url:)` for a file that does not exist
- **THEN** the terminal method throws `HokusaiError.io` for a read operation

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
SHALL return a new pipeline, SHALL leave its input pipeline usable for a
separate branch, and SHALL be applied in call order. Transformations SHALL
validate their options immediately and SHALL NOT perform native work;
validation that depends on pixel data SHALL be reported at evaluation.
Composite layers SHALL contribute only their image transformations; a
layer's encoder and metadata settings SHALL be ignored.

#### Scenario: Branch a base pipeline

- **WHEN** a caller derives two pipelines with different transformations from
  one base pipeline
- **THEN** both derived pipelines can be evaluated independently
- **AND** the base pipeline remains unchanged

#### Scenario: Preserve operation order

- **WHEN** a caller applies `resize` then `extract`, or `extract` then
  `resize`, to the same source
- **THEN** each output reflects its own operation order

#### Scenario: Validate dimensions before native work

- **WHEN** a caller requests a resize or extract with a non-positive dimension
- **THEN** the operation throws a typed validation error

#### Scenario: Report pixel-dependent errors at evaluation

- **WHEN** a caller extends a pipeline to a canvas smaller than the image
- **THEN** the terminal method throws `HokusaiError.invalidOption`

#### Scenario: Ignore a layer's output configuration

- **WHEN** a composite layer pipeline has its own encoder or metadata policy
- **THEN** the composited output is identical to using the layer without them

### Requirement: Produce typed asynchronous outputs

The library SHALL provide asynchronous `data()` and `write(to:)` terminals.
Both SHALL open the source, build the native graph, and encode within the
terminal execution boundary, using the same evaluation semantics. They SHALL
return encoded output with dimensions, format, and byte-size metadata.
Terminal evaluation SHALL not occupy Swift's cooperative executor.

#### Scenario: Encode an explicitly selected format

- **WHEN** a caller selects JPEG, PNG, WebP, AVIF, or PDF and calls `data()`
- **THEN** the returned `Output` contains bytes and `OutputInfo` for that
  format

#### Scenario: Infer output format from destination

- **WHEN** no encoder is selected and a caller calls `write(to:)` with a
  supported file extension
- **THEN** the library writes the file using that inferred format

#### Scenario: Data and file terminals agree

- **WHEN** a caller evaluates the same pipeline with `data()` and
  `write(to:)`
- **THEN** the written file contains the same bytes and `OutputInfo`
