## 1. Native ownership

- [x] 1.1 Add `NativeImage` as the single owning libvips handle
- [x] 1.2 Move loading, encoding, metadata, and operation implementations onto `NativeImage`
- [x] 1.3 Reduce `VipsBackend` and `HokusaiImage` to facades over `NativeImage`

## 2. Plan and evaluator

- [x] 2.1 Add `ImagePlan`, `ImageSource`, `ImageOperation`, `LayerStep`, `TerminalConfig`
- [x] 2.2 Add `Evaluator` lowering plans to native graphs and driving data/file sinks
- [x] 2.3 Move pipeline error mapping to `HokusaiError.pipeline`

## 3. Public pipeline

- [x] 3.1 Store plan + terminal config in `Hokusai`; remove optional legacy state
- [x] 3.2 Make construction and transforms record intent without native work
- [x] 3.3 Run lowering and encoding inside `PipelineExecutor` for `data()` and `write(to:)`

## 4. Tests and docs

- [x] 4.1 Swift Testing coverage for order, branching, laziness, error timing, sink parity, layer isolation, source lifetime
- [x] 4.2 README and CHANGELOG describe lazy evaluation and error timing
