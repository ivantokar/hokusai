# Test layout

The suite has layers with different jobs, so a failure says what kind of
guarantee broke.

| Layer | Target | Imports | Owns |
| --- | --- | --- | --- |
| A. Public semantics | `HokusaiPublicTests` | `Hokusai` and the other public products (`HokusaiNIO`) | Documented behaviour: operation semantics and order, orientation, sink parity, typed errors, limits, cancellation, `Sendable` |
| B. Internal | `HokusaiTests` | `@testable Hokusai`, `CVips` | Planner traces, optimiser equivalence, native lifetime, capability mapping, the private scheduler, CLI parsing |
| C. Process / stress / benchmark | `HokusaiProcessTests` | nothing; it launches `HokusaiProcessProbe` | Runtime variants that freeze process-global configuration, scheduler capacity sweeps, overload, cancellation, blocked loaders, memory growth. Sanitizers run in a separate non-gating workflow; base-versus-candidate benchmarks run in an advisory workflow |

Rules of thumb:

- A public behaviour is covered in layer A. Layer B may add to it but never replaces it.
- Layer A never asserts a libvips operation name or native message.
- Encoded bytes are not an oracle. Compare decoded pixels with an explicit
  tolerance (`expectPixels(_:match:_:)`: `.exact`, `.absolute`, `.aggregate`);
  failures name the first and worst differing pixel.
- Layer A needs no native helper. `RasterSupport.swift` builds inputs and reads
  outputs through an uncompressed TIFF, which keeps the oracle independent of
  the codecs under test.
- Layer A keeps its own small copy of the fixtures it reads in
  `HokusaiPublicTests/Fixtures` (`fixtureData(named:ext:)`). A symlink to layer
  B's directory does not work: Swift 6.0 on Linux leaves it dangling in the
  resource bundle.
- Optional codecs (GIF, AVIF, HEIF, ...) are skipped only after asking
  `Hokusai.capabilities()`. A missing baseline capability must fail.

Layer B no longer repeats layer A: the content-aware and multi-page suites
that only asserted public behaviour were removed once their layer A versions
landed. One test stays in B (`trimHandlesGreyImages`) because it needs a
single-band input that layer A's RGBA helpers cannot build.

`PipelineAPITests` and `LifecycleConcurrencyTests` are gone: tests with a
layer A twin were dropped, the rest moved to `LifecycleAndInteropTests`
(initialization, shared-source concurrency, source ownership, NIO, AVIF).

Layer C starts `HokusaiProcessProbe` (an executable target, not a product) as
a fresh process per scenario and reads its `key=value` report. Add a scenario
to the probe and a test that runs it; never freeze configuration inside the
test process. `HOKUSAI_STRESS_ITERATIONS` lengthens the memory test, and
`HOKUSAI_PROBE` points at a probe binary when the default lookup fails.

Sanitizers (`.github/workflows/sanitizers.yml`) run the whole suite under
AddressSanitizer and ThreadSanitizer on Linux. The workflow is never a PR gate;
the ThreadSanitizer job is informative until native-library false positives are
understood. Run it on a branch with `gh workflow run sanitizers.yml --ref <branch>`
once the file is on the default branch, or let a PR that edits it trigger it.

`.github/workflows/benchmark.yml` builds the base and the candidate of a pull
request to `release/2.0` on one runner and compares them with
`hokusai benchmark compare` (latency and peak resident memory), in the order
base, candidate, candidate, base so the two base runs show the runner's noise.
It is advisory and never fails on a slowdown. Time to first byte waits for the
streaming API.

Still open under #50: fresh-process runtime variants, sanitizer jobs, the
benchmark harness (base-versus-candidate on one runner, memory and
time-to-first-byte), and the streaming/backpressure and vector-PDF suites that
depend on features not shipped yet.
