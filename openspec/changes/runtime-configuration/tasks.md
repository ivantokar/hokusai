## 1. Configuration

- [x] 1.1 `RuntimeConfiguration`, `ConcurrencyLimit`, validation
- [x] 1.2 `ConfigurationState`: configure once, freeze on first use
- [x] 1.3 Apply `vipsConcurrency` at initialization; scheduler limit and queue bound from the frozen configuration
- [x] 1.4 `HokusaiError.overloaded` for a full queue
- [x] 1.5 Remove `Hokusai.vipsConcurrency`

## 2. Capabilities and status

- [x] 2.1 Operation-based loader/saver discovery, Cairo PDF check, AVIF round-trip probe
- [x] 2.2 Cached `Hokusai.capabilities()`
- [x] 2.3 `Hokusai.runtimeStatus` without initializing libvips

## 3. CLI, tests, docs

- [x] 3.1 `hokusai info` prints capabilities and settings; benchmark configures at startup; remove `--concurrency-sweep`
- [x] 3.2 Tests: validation, freeze, configure-once state, capabilities, concurrent reads, queue bound and counters
- [x] 3.3 README runtime section, CHANGELOG, benchmark notes
