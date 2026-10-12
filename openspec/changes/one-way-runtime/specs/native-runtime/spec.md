## MODIFIED Requirements

### Requirement: Initialize libvips safely

The library SHALL initialize libvips automatically before the first native
operation and SHALL initialize it at most once per process, including under
concurrent first use. `Hokusai.initialize()` SHALL be safe to call repeatedly
and concurrently and SHALL surface initialization failures as
`HokusaiError.initializationFailed`. Once initialized, libvips SHALL remain
available for the lifetime of the process; Hokusai SHALL NOT tear it down.

#### Scenario: Repeated initialization

- **WHEN** an application calls `Hokusai.initialize()` multiple times
- **THEN** every successful call leaves the runtime usable
- **AND** only one native initialization occurs

#### Scenario: Concurrent first use

- **WHEN** many tasks call `Hokusai.initialize()` concurrently before any
  other Hokusai use
- **THEN** every call succeeds and libvips is initialized once

## REMOVED Requirements

### Requirement: Enforce final shutdown semantics

**Reason**: libvips shutdown is optional, irreversible, and unsafe for
long-running servers; supporting it required runtime state, locking, and
live-image accounting with no benefit to ordinary applications.

**Migration**: Remove calls to `Hokusai.shutdown()`. The operating system
reclaims libvips resources at process exit.
