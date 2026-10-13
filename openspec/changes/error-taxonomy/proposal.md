## Why

`HokusaiError` mixed a modern taxonomy with fourteen legacy, backend-specific
cases, `FailureContext.message` mixed Hokusai's explanation with libvips'
process-global log text, and a catch-all `pipeline(...)` mapper stringified
arbitrary errors into a caller-chosen category. #42 (roadmap #52, Phase 1)
makes errors one contract classified where they happen.

## What Changes

- **BREAKING** One taxonomy: `invalidInput(reason:)`, `invalidOption`,
  `unsupported(feature:reason:)`, `decode`, `transform`, `encode`, `io`,
  `resource(ResourceFailure)`, `runtime`. Cancellation stays Swift's
  `CancellationError`.
- **BREAKING** `FailureContext` = `operation` + `reason` + optional
  `diagnostic`; the native text is best-effort and never classifies.
- **BREAKING** Remove all legacy cases (`initializationFailed`, `loadFailed`,
  `saveFailed`, `invalidOperation`, `invalidDimensions`, `unsupportedFormat`,
  `conversionFailed`, `textRenderingFailed`, `vipsError`, `magickError`,
  `memoryAllocationFailed`, `fileNotFound`, `invalidImageData`,
  `notSupported`). Legacy `HokusaiImage` APIs throw modern cases.
- `ResourceFailure` / `ResourceKind` (struct, extensible) replace the
  `overloaded` case from #28.
- `VipsDiagnostics` drains libvips' log in one place and documents that it is
  not request-scoped.
- Boundaries classify: source (`io(.read)`, `invalidInput`, `decode`),
  operations (`transform`, `unsupported` text), encoders (`unsupported`
  when the build lacks the encoder, else `encode`), PDF file sink
  (`io(.write)`), scheduler (`resource`), initialization (`runtime`).
  Composite layer failures are scoped (`composite layer 2 / ...`).
- Remove `HokusaiError.pipeline(...)`.

libvips file savers report encoder and file failures alike, so their
failures stay `encode` with a diagnostic; #40 introduces target sinks that
can report `io(.write)` precisely.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `image-pipeline`: adds the error-classification requirement.

## Impact

- Public API: `HokusaiError` cases and `FailureContext` fields change;
  callers switching on legacy cases must migrate.
- CLI and output formats: unchanged.
