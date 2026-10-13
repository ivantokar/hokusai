## Why

Process-wide libvips state was exposed as an ad hoc mutable setter
(`Hokusai.vipsConcurrency`), the scheduler limit from #41 was not
configurable, and operators could not ask which codecs the linked build
supports or how loaded the scheduler is. #28 (roadmap #52, Phase 1) adds one
typed process-level surface.

## What Changes

- `Hokusai.configure(_ RuntimeConfiguration)`: `maxConcurrentEvaluations`,
  `maxQueuedEvaluations`, `vipsConcurrency` (`ConcurrencyLimit`: `.automatic`
  or `.fixed(n)`). Validated first; callable once; frozen at the first
  `initialize()`, `capabilities()`, or terminal evaluation.
- `Hokusai.capabilities()` (throwing, cached): libvips version, decodable and
  encodable `ImageFormat`s, text rendering. AVIF verified by round trip; PDF
  input and Cairo PDF output reported separately.
- `Hokusai.runtimeStatus`: configuration, frozen flag, queued/active
  evaluations, effective limits; never initializes libvips.
- Scheduler queue bound: a full queue throws the new
  `HokusaiError.resource` (kind `.queuedEvaluations`).
- **BREAKING** Remove `Hokusai.vipsConcurrency` and the CLI
  `--concurrency-sweep` flag (process-isolated sweeps belong to #50).
- `hokusai info` prints capabilities and effective settings.

Deferred: libvips cache/SIMD controls and an untrusted-operation security
mode (evaluated, not exposed: no stable typed contract yet); benchmark-chosen
`.automatic` limit (#50); extending `ImageFormat` (JXL, JP2K) (#23/#51).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `native-runtime`: adds runtime configuration, capability reporting, and
  status requirements.

## Impact

- Public API: new `configure`, `capabilities`, `runtimeStatus`,
  `RuntimeConfiguration`, `ConcurrencyLimit`, `RuntimeCapabilities`,
  `RuntimeStatus`, `HokusaiError.resource` (kind `.queuedEvaluations`); `vipsConcurrency` removed.
- CLI: `info` output extended; benchmark `--concurrency-sweep` removed.
- Output formats: unchanged.
