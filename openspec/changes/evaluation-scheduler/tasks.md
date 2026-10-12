## 1. Scheduler

- [x] 1.1 Asynchronous FIFO admission gate with cancellable waiters and exact slot accounting
- [x] 1.2 Dispatch queue runs only admitted work; no hard-coded QoS
- [x] 1.3 Replace `PipelineExecutor` with `EvaluationScheduler.shared`

## 2. Cancellation

- [x] 2.1 `EvaluationContext` with lock-guarded cancellation and registered sink image
- [x] 2.2 Private pass-through sink outside the operation cache; `vips_image_set_kill` on cancel
- [x] 2.3 Check cancellation between lowering steps; map post-cancel failures to `CancellationError`
- [x] 2.4 Remove `HokusaiError.cancelled`

## 3. Tests and docs

- [x] 3.1 FIFO/suspended waiters, queued cancellation, slot release, single-slot composites
- [x] 3.2 Running cancellation, sibling isolation, re-evaluation after cancel
- [x] 3.3 Concurrent failures keep typed context
- [x] 3.4 README, CHANGELOG, corrected error-buffer comments
