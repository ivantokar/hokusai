## Why

Today `Hokusai` stores an already-opened native graph (`HokusaiImage?`):
`Hokusai(data:)` decodes immediately and every transform calls libvips on the
caller's thread. Source intent is lost before evaluation (blocking #20
shrink-on-load), native work runs outside the bounded executor, and the
optional `pipeline` exists only for legacy static APIs. #34 (roadmap #52,
Phase 1) replaces that with an immutable plan evaluated only at terminals.

## What Changes

- `Hokusai` stores an immutable `ImagePlan` (source + ordered operations, a
  DAG through composite layers) and a separate `TerminalConfig` (encoder +
  metadata policy). No optional legacy state.
- Transforms validate options synchronously and append plan steps; they do no
  native work.
- One internal evaluator lowers a plan to a libvips graph inside the terminal
  execution boundary and drives the encoder/file sink for both `data()` and
  `write(to:)`.
- Native operation code moves from `HokusaiImage` extensions to functions over
  an internal RAII `NativeImage`. Legacy `HokusaiImage` methods become thin
  wrappers, so the evaluator never touches `HokusaiImage`.
- **BREAKING (behavioral)** Decode failures, missing files, and
  dimension-dependent errors (e.g. `extend` smaller than the image) surface at
  `data()`/`write(to:)`/`metadata()` instead of at construction or at the
  transform call. Option validation that needs no pixels stays synchronous.
- `metadata()` keeps its synchronous signature for now and lowers the plan on
  the caller; its async/source-vs-output semantics are #43/#24.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `image-pipeline`: construction is lazy; native failures surface at terminal
  evaluation; output configuration never evaluates; composite layers
  contribute only their image plan.

## Impact

- Public API signatures: unchanged.
- Behavior: error timing as above; outputs are pixel-identical.
- CLI: commands that relied on eager decode errors still fail, at evaluation.
- Code: `Hokusai.swift` (rewritten storage), new `Plan/` and `Evaluation/`
  directories, `Operations/*` native code extracted to `NativeImage`
  functions, `PipelineExecutor` wraps lowering + encoding until #41 replaces it.
