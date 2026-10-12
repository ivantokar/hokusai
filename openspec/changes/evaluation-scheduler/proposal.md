## Why

`PipelineExecutor` blocked a Dispatch worker on a semaphore for every waiting
evaluation, checked cancellation only on a thread that is not the caller's
task, could not stop running libvips work, and reported cancellation as a
Hokusai-specific error. #41 (roadmap #52, Phase 1) replaces it.

## What Changes

- New internal `EvaluationScheduler`: an asynchronous FIFO admission gate
  (suspended waiters, cancellable while queued) in front of a Dispatch queue
  that runs only admitted native work. One terminal evaluation holds one
  slot; composite subplans never acquire another.
- New internal `EvaluationContext`: cancellation state shared with
  `withTaskCancellationHandler`. Before encoding, the final image is wrapped in
  a private pass-through image outside libvips' operation cache and
  registered; cancelling the task calls `vips_image_set_kill` on it, so
  running work stops without affecting concurrent evaluations that share
  cached upstream images.
- **BREAKING** Cancellation throws Swift `CancellationError`;
  `HokusaiError.cancelled` is removed.
- The Dispatch queue no longer hard-codes `.userInitiated` QoS.
- Comments no longer claim libvips' global error buffer is request-atomic.

Deferred: public `maxConcurrentEvaluations` / pending-queue bounds /
observability (#28); benchmark-chosen automatic limit and the
two-dimensional benchmark matrix (#50); async `metadata()` through the
scheduler (#43). The default limit stays `activeProcessorCount` until then.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `native-runtime`: adds terminal scheduling and cancellation requirements.

## Impact

- Public API: `HokusaiError.cancelled` removed; terminals throw
  `CancellationError`.
- CLI and output formats: unchanged.
- Files: `Sources/Hokusai/Execution/EvaluationScheduler.swift` (replaces
  `PipelineExecutor.swift`), `Evaluator.swift`, `Hokusai.swift`,
  `HokusaiError.swift`, `CVips/shim.h`, tests, README, CHANGELOG.
