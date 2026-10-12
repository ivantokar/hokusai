## Context

Current modern operations each create a native node at call time. Native
operation logic (resize fit/embed math, attention crop, rotation, text,
composite) lives in `HokusaiImage` extensions shared with the legacy API.
`PipelineExecutor` bounds only encoding/writing. Composite layers are other
`Hokusai` values whose already-built native graphs are reused.

## Goals / Non-Goals

**Goals:** plan/terminal separation; no native work during chaining; one
evaluator for every terminal; evaluator independent of `HokusaiImage`;
representation that #20, #21, #25, #38, #39 can extend without redesign.

**Non-Goals:** new operations or semantic fixes (#35/#37), cancellation inside
native evaluation (#41), input policy (#21), planner rewrites (#39), public
metadata redesign (#24/#43), deleting legacy API (#32).

## Decisions

### 1. Plan representation: indirect enum, shared by value

```swift
public struct Hokusai: Sendable {
    let plan: ImagePlan
    let terminal: TerminalConfig
}

indirect enum ImagePlan: Sendable {
    case source(ImageSource)
    case apply(ImageOperation, to: ImagePlan)
}

enum ImageSource: Sendable {
    case file(URL)
    case data(Data)                     // Data is CoW: branches share bytes
    // later: input options (#21), .generated(TextSource) (#38), .raw(...) (#22)
}

enum ImageOperation: Sendable {         // not `Operation`: clashes with Foundation
    case autoOrient
    case resize(ResizeStep)
    case rotate(degrees: Double, background: Color)
    case flip, flop
    case extract(x: Int, y: Int, width: Int, height: Int)
    case extend(ImageSize, CanvasAnchor, Color)
    case trim(threshold: Double)
    case blur(sigma: Double), sharpen(sigma: Double)
    case grayscale, tint(Color), normalize, convert(ColorSpace)
    case ensureAlpha, flatten(Color)
    case composite([LayerStep])          // LayerStep holds an ImagePlan → DAG
    case drawText(String, x: Int, y: Int, TextOptions)
}

struct TerminalConfig: Sendable {
    var encoder: OutputFormat?
    var preservesMetadata = false
}
```

Indirect enum payloads are immutable boxes, so branching shares the prefix
without copying and is `Sendable` with no `@unchecked`. Composite layers hold
the layer's `ImagePlan` only, so a layer's encoder can never trigger an
intermediate encode. Generated sources and raw input are new `ImageSource`
cases; DAG nodes are `composite` payloads.

Rejected: `[Operation]` (cannot express layers without a second structure);
`final class` nodes for identity-based memoization (no measured need — libvips'
operation cache already dedupes identical subgraphs; revisit in #39).

`ImageOperation` and `ImageSource` are internal. #51 decides what, if anything, is
public.

### 2. Evaluator: lower plan → `NativeImage`, then sink

```swift
final class NativeImage {               // RAII; not Sendable; one evaluation only
    let pointer: UnsafeMutablePointer<VipsImage>
    deinit { g_object_unref(pointer) }
}

enum Evaluator {
    static func lower(_ plan: ImagePlan) throws -> NativeImage
    static func encode(_ plan: ImagePlan, _ terminal: TerminalConfig, as: OutputFormat) throws -> Output
    static func write(_ plan: ImagePlan, _ terminal: TerminalConfig, as: OutputFormat, to: URL) throws -> OutputInfo
}
```

`lower` walks the plan iteratively from the source, applying operations in
order; composite layers are lowered in the same call (no nested scheduling).
`data()`/`write(to:)` call `PipelineExecutor.run { Evaluator.encode/write }`,
so source opening and graph construction happen inside the bounded executor.
#41 later replaces `PipelineExecutor` without changing the evaluator.

Errors from each step are wrapped with that step's operation name
(`HokusaiError.decode/transform/encode`), keeping today's typed categories.

### 3. Native operation code moves to `NativeImage`

Each `HokusaiImage` operation extension is split into a function on
`NativeImage` (the native logic, moved verbatim) and a one-line legacy wrapper.
`VipsBackend` adopts `NativeImage` for ownership. This keeps one native
implementation per operation, makes the evaluator independent of
`HokusaiImage`, and leaves #32 to delete the wrappers.

Rejected: a temporary `NativeImage → HokusaiImage` bridge in the evaluator —
less code now, but it violates #34's "evaluation does not depend on
`HokusaiImage`" and every operation-family PR would have to redo it.

### 4. Lazy construction and error timing

`Hokusai(data:)`/`Hokusai(url:)` validate arguments (file URL, non-empty data,
supported `InputOptions`) but do not open the source. Decode errors, missing
files, and pixel-dependent validation (`extend` that would shrink,
`ensureAlpha`'s alpha check, `trim` bounds) happen during lowering.

This matches Sharp (`sharp(input)` never throws on content) and is required for
#20: the loader cannot be chosen until the whole plan is known.

### 5. `metadata()`

Stays synchronous and lowers the plan on the caller, the same cost as today.
#43 makes it async and separates source-header from pipeline metadata.

## Risks / Trade-offs

- Error timing changes for callers who expected `Hokusai(data:)` to reject
  invalid bytes → documented in CHANGELOG; callers who need early rejection
  call `metadata()` (and, after #43, async source inspection).
- Repeated `data()` on one value re-lowers the plan → cheap (libvips caches
  load/operation results); same cost model as Sharp.
- Moving operation code touches every operation file → mechanical moves, no
  semantic edits, covered by existing pixel tests.

## Migration Plan

One PR into `release/2.0`, in commits: (1) `NativeImage` + extract native
operation functions, legacy wrappers delegate; (2) `ImagePlan`/`Operation`/
`Evaluator`; (3) switch `Hokusai` storage and terminals; (4) tests and spec.
