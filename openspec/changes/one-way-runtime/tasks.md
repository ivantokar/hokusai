## 1. Runtime

- [x] 1.1 Add `VipsRuntime.ensureInitialized()` using one-time static initialization
- [x] 1.2 Route `Hokusai.initialize()` and native load entry points through `VipsRuntime`
- [x] 1.3 Remove `RuntimeState`, `runtimeLock`, `liveImageCount`, and `VipsBackend.shutdown()`
- [x] 1.4 Remove public `Hokusai.shutdown()`

## 2. Tests and docs

- [x] 2.1 Remove the shutdown-only test; keep repeated and concurrent initialization tests
- [x] 2.2 Correct stale lifecycle comments
- [x] 2.3 Update README runtime lifecycle and CHANGELOG
