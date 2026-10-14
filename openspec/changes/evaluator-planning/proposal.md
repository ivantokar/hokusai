## Why

#34 gave Hokusai an immutable plan and one evaluator, but nothing says which
rewrites the evaluator may perform. Without explicit rules, later issues (#20
shrink-on-load, #25 array composite) would each invent their own and risk
changing what a written pipeline means. #39 (roadmap #52, Phase 2) fixes the
rules and implements the small whitelist that needs no new operations.

## What Changes

- A `Planner` with a whitelisted `PlannerRule` set. The plan it produces is
  always one-to-one with the written operations, in order.
  - `identityRotation`: rotation by an exact whole number of turns.
  - `emptyComposite`: compositing no layers.
  - `subplanMemoisation`: within one evaluation, a plan node reached by
    several consumers is built once. Keyed by node identity, scoped to the
    evaluation, never applied to `.sequential` sources.
- `ImagePlan` is rebuilt on immutable class nodes (same API) so node identity
  exists; branching still shares prefixes.
- Internal `PlanTrace` records source opens, lowered and skipped operations,
  memoisation hits, and the terminal sink, for tests and benchmarks. No
  public API.
- `PlannerOptions` lets tests disable rules, with `.reference` turning every
  optimisation off, so each rule is compared with the unoptimised lowering.
- The terminal sink is recorded: everything but PDF encodes directly to a
  memory buffer or file.

Not done here: shrink-on-load eligibility and application (#20), array
`vips_composite` lowering (#25), and everything on the deferred list in
design.md.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `image-pipeline`: adds the order-preservation and per-evaluation sharing
  requirements.

## Impact

- Public API: unchanged.
- Behavior: output is unchanged; a shared source or layer is decoded once per
  evaluation instead of once per use.
- Internal: `ImagePlan`, `Planner`, `PlanTrace`, `EvaluationContext`.
