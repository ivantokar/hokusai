## Why

`Hokusai.shutdown()` drives a runtime state machine, a process-wide lock, and
a live-image counter that exist only to make teardown safe. libvips documents
`vips_shutdown()` as optional and irreversible, and long-running servers must
never call it. The next-major evaluator (#34) should build on a runtime whose
only job is to initialize libvips once (#33, roadmap #52 Phase 1).

## What Changes

- **BREAKING** Remove `Hokusai.shutdown()` (deprecated in 1.0).
- Move initialization out of `VipsBackend` into a process-level `VipsRuntime`
  that initializes libvips at most once via Swift one-time static
  initialization; an initialization failure is final for the process.
- Remove `RuntimeState`, `runtimeLock`, and `liveImageCount` from the image
  ownership type.
- `Hokusai.initialize()` remains as an optional startup preflight; native
  entry points still initialize automatically.

Process-wide configuration such as `Hokusai.vipsConcurrency` is unchanged and
is redesigned in #28.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `native-runtime`: initialization becomes one-way and process-scoped; the
  final-shutdown requirement is removed.

## Impact

- Public API: `Hokusai.shutdown()` removed. Callers delete the call; there is
  no replacement.
- CLI and output formats: unchanged.
- Files: `Sources/Hokusai/Runtime/VipsRuntime.swift`,
  `Sources/Hokusai/Backend/VipsBackend.swift`, `Sources/Hokusai/Hokusai.swift`,
  lifecycle tests, `README.md`, `CHANGELOG.md`.
