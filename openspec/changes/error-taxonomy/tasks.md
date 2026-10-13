## 1. Taxonomy

- [x] 1.1 New `HokusaiError` cases, `FailureContext(operation, reason, diagnostic)`, `ResourceFailure`, `ResourceKind`
- [x] 1.2 Remove legacy cases and `HokusaiError.pipeline`
- [x] 1.3 `VipsDiagnostics` as the single best-effort log drain

## 2. Boundary classification

- [x] 2.1 Sources: `invalidInput`, `io(.read)`, `decode`
- [x] 2.2 Operations: `transform`, text `unsupported`, allocation `runtime`
- [x] 2.3 Encoders: capability check → `unsupported`, failure → `encode`; PDF file write → `io(.write)`
- [x] 2.4 Scheduler queue → `resource(.queuedEvaluations)`; initialization → `runtime`
- [x] 2.5 Composite layer scoping

## 3. Tests and docs

- [x] 3.1 Per-boundary tests; no assertions on native text
- [x] 3.2 Migrate legacy error tests
- [x] 3.3 README errors section, CHANGELOG
