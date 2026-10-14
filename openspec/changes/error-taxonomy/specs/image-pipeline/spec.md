## ADDED Requirements

### Requirement: Classify failures where they occur

The library SHALL report processing failures as one `HokusaiError` taxonomy:
`invalidInput`, `invalidOption`, `unsupported`, `decode`, `transform`,
`encode`, `io`, `resource`, and `runtime`. Each case SHALL be chosen by the
boundary where the failure occurred and SHALL NOT be inferred from native
diagnostic text. Native diagnostics SHALL be exposed only as optional,
best-effort detail. Task cancellation SHALL throw `CancellationError`.

#### Scenario: Missing source file

- **WHEN** a pipeline reads a file that does not exist
- **THEN** the terminal throws `HokusaiError.io` with a read operation

#### Scenario: Corrupt source bytes

- **WHEN** a pipeline decodes bytes that are not a valid image
- **THEN** the terminal throws `HokusaiError.decode`

#### Scenario: Failed native operation

- **WHEN** an operation fails after its options were validated, such as an
  extract outside the image
- **THEN** the terminal throws `HokusaiError.transform` naming the operation

#### Scenario: Failed encoder

- **WHEN** an available encoder cannot encode the image
- **THEN** the terminal throws `HokusaiError.encode`

#### Scenario: Failure inside a composite layer

- **WHEN** a composite layer's source cannot be decoded
- **THEN** the terminal throws `HokusaiError.decode` whose operation names
  the layer
