## Context

libvips already evaluates lazily, caches recent operation calls, and threads
its own workers. Hokusai only needs planning that depends on knowledge of the
Swift pipeline: what the caller wrote, which values are shared, and which
source options were chosen.

## Goals / Non-Goals

**Goals:** a written whitelist of equivalence-preserving rules; each rule
testable against an unoptimised lowering; enough trace to prove which path ran.

**Non-Goals:** a general optimiser, a public optimiser API, reordering, a
Hokusai-level result cache.

## Decisions

### Whitelist, not a framework

Rules are enum cases checked in two places: the pure `Planner.plan` (identity
operations) and `Evaluator.build` (memoisation). There is no rule protocol or
registry. A new rule must add a case, a reference-comparison test, and an
entry here.

### The planned list is 1:1 with the written list

Skipped operations stay in the list marked with their rule. Node identity
(for memoisation) and the trace therefore line up with what the caller wrote,
and "the planner reorders or drops operations" is not representable.

### Identity rules are exact

A rotation is an identity only when `degrees % 360 == 0`. These are
explicitly not identities, because each carries a contract of its own: resize
to unchanged dimensions (resampling), colour conversion that looks equivalent
(interpretation and metadata), `extend` to the current size, blend operations
with zero-looking inputs, a vanishing blur sigma.

### Memoise by node identity, per evaluation

`ImagePlan` nodes are immutable classes, so `ObjectIdentifier` identifies a
node across every plan derived from it. The evaluation context keeps a map from
node to native image for the duration of one terminal evaluation and releases
it with the context. Structurally equal plans from independent `Hokusai`
values are never merged (proving equivalence is not worth a hidden
cross-value cache). `.sequential` sources are excluded: one forward-only
stream cannot serve two readers.

### Deferred

Cross-operation reordering; fusing consecutive resizes or geometry; automatic
gamma around resize; automatic `copy_memory`/tile caches for shared subgraphs;
a process-wide evaluated-pipeline cache; automatic `.sequential` selection;
structural deduplication; lossy approximation. Each needs its own
benchmark-backed proposal.

## Risks / Trade-offs

- Memoised nodes keep their native images until the evaluation ends. They are
  lazy graph nodes the final graph references anyway, so peak memory does not
  grow; materialised buffers still belong to the sources that own them.
- Trace and planner switches are internal; if a future caller needs them they
  must be designed deliberately rather than leaked.
