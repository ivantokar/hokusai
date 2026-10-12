## ADDED Requirements

### Requirement: Schedule terminal evaluations

Terminal evaluations SHALL be admitted in FIFO order up to a concurrency
limit that is independent of libvips' worker-thread concurrency. Waiting
evaluations SHALL remain suspended tasks and SHALL NOT start native work. One
terminal evaluation SHALL hold exactly one slot, including all composite
layers and other subplans it evaluates. Slots SHALL be released after
success, failure, and cancellation.

#### Scenario: More callers than slots

- **WHEN** more evaluations are requested than the limit allows
- **THEN** only the admitted evaluations run native work
- **AND** the others start in request order as slots are released

#### Scenario: Composite layers do not take extra slots

- **WHEN** a pipeline with composite layers is evaluated with a single slot
- **THEN** evaluation completes without waiting for another slot

### Requirement: Cancel terminal evaluations

Cancelling the task that awaits a terminal SHALL throw Swift's
`CancellationError`. A queued evaluation SHALL leave the queue without
starting native work. A running evaluation SHALL ask libvips to stop and SHALL
throw `CancellationError` when native work observes the request; if the
evaluation already completed, its result SHALL be returned. Cancellation
SHALL NOT affect other evaluations of the same pipeline, and the pipeline
SHALL remain usable for later evaluation.

#### Scenario: Cancel a queued evaluation

- **WHEN** an evaluation is cancelled while waiting for a slot
- **THEN** it throws `CancellationError` and never starts native work

#### Scenario: Cancel a running evaluation

- **WHEN** an evaluation is cancelled while libvips is computing pixels
- **THEN** it throws `CancellationError` promptly
- **AND** a concurrent evaluation of the same pipeline completes normally
- **AND** evaluating the pipeline again succeeds
