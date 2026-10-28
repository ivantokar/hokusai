# Test layout

The suite has layers with different jobs, so a failure says what kind of
guarantee broke.

| Layer | Target | Imports | Owns |
| --- | --- | --- | --- |
| A. Public semantics | `HokusaiPublicTests` | `Hokusai` only | Documented behaviour: operation semantics and order, orientation, sink parity, typed errors, limits, cancellation, `Sendable` |
| B. Internal | `HokusaiTests` | `@testable Hokusai`, `CVips` | Planner traces, optimiser equivalence, native lifetime, capability mapping, the private scheduler, CLI parsing |
| C. Process / stress / benchmark | not yet | — | Runtime variants that freeze process-global configuration, sanitizers, benchmarks |

Rules of thumb:

- A public behaviour is covered in layer A. Layer B may add to it but never replaces it.
- Layer A never asserts a libvips operation name or native message.
- Encoded bytes are not an oracle. Compare decoded pixels with an explicit
  tolerance (`expectPixels(_:match:_:)`: `.exact`, `.absolute`, `.aggregate`);
  failures name the first and worst differing pixel.
- Layer A needs no native helper. `RasterSupport.swift` builds inputs and reads
  outputs through an uncompressed TIFF, which keeps the oracle independent of
  the codecs under test.
- Optional codecs (GIF, AVIF, HEIF, ...) are skipped only after asking
  `Hokusai.capabilities()`. A missing baseline capability must fail.

Still open under #50: fresh-process runtime variants, sanitizer jobs, the
benchmark harness (base-versus-candidate on one runner, memory and
time-to-first-byte), and the streaming/backpressure and vector-PDF suites that
depend on features not shipped yet.
