## ADDED Requirements

### Requirement: Configure the runtime once at startup

The library SHALL accept one process-wide `RuntimeConfiguration` through
`Hokusai.configure(_:)`, validating every value before recording it. The
configuration SHALL freeze at the first `initialize()`, `capabilities()`, or
terminal evaluation; building pipelines SHALL NOT freeze it. Configuring
twice, or after the configuration froze, SHALL throw a typed
`HokusaiError.runtime` error.

#### Scenario: Reject invalid configuration

- **WHEN** a caller configures a non-positive evaluation limit or libvips
  concurrency, or a negative queue bound
- **THEN** `configure(_:)` throws `HokusaiError.invalidOption` naming the field

#### Scenario: Reject configuration after first use

- **WHEN** a caller configures the runtime after a terminal evaluation
- **THEN** `configure(_:)` throws `HokusaiError.runtime`

### Requirement: Bound pending evaluations

The evaluation limit SHALL be independent of libvips worker concurrency. When
`maxQueuedEvaluations` is set, an evaluation that would exceed it SHALL fail
with `HokusaiError.overloaded` without starting native work.

#### Scenario: Reject work beyond the queue bound

- **WHEN** all evaluation slots are busy and the queue holds
  `maxQueuedEvaluations` waiters
- **THEN** a new evaluation throws `HokusaiError.overloaded`
- **AND** queued and active counts are unchanged

### Requirement: Report native capabilities

`Hokusai.capabilities()` SHALL report the linked libvips version, the
`ImageFormat`s the build can decode, the formats Hokusai's typed encoders can
produce with it, and whether text rendering is available. It SHALL throw if
libvips cannot be initialized. AVIF SHALL be reported only when encoding and
decoding actually work. PDF input and PDF output SHALL be reported
independently. The result SHALL be immutable and safe to share.

#### Scenario: Query the baseline build

- **WHEN** a caller queries capabilities on a supported build
- **THEN** JPEG, PNG, and WebP are decodable and encodable
- **AND** PDF output is encodable

### Requirement: Report runtime status

`Hokusai.runtimeStatus` SHALL report the effective configuration, whether it
is frozen, queued and active evaluation counts, the effective evaluation
limit, and libvips' effective worker concurrency once initialized. Reading it
SHALL NOT initialize libvips or freeze configuration.

#### Scenario: Read status concurrently

- **WHEN** many tasks read `runtimeStatus` concurrently
- **THEN** each snapshot reports at most the evaluation limit as active
