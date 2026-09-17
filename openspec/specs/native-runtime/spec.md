# Native Runtime Specification

## Purpose

Define the process-wide libvips lifecycle, native ownership, and concurrency
contracts that keep Hokusai safe for server-side use.

## Requirements

### Requirement: Initialize libvips safely

The library SHALL initialize libvips automatically at image-loading entry
points. `Hokusai.initialize()` SHALL be safe to call repeatedly and
concurrently, and SHALL surface initialization failures as `HokusaiError`.

#### Scenario: Repeated initialization

- **WHEN** an application calls `Hokusai.initialize()` multiple times
- **THEN** every successful call leaves the runtime usable
- **AND** only one native initialization occurs

### Requirement: Enforce final shutdown semantics

`Hokusai.shutdown()` SHALL be an explicit final process-teardown operation.
It SHALL refuse to shut down while native image handles are alive, SHALL be
idempotent before initialization, and SHALL prevent a later reinitialization
after a successful shutdown.

#### Scenario: Reject shutdown with live images

- **WHEN** an image handle is alive and a caller requests shutdown
- **THEN** shutdown throws a typed invalid-operation error
- **AND** the image remains usable

### Requirement: Preserve immutable concurrent use

Image pipelines and their underlying libvips image handles SHALL be safe to
read and evaluate from concurrent tasks. Native image ownership SHALL be
released exactly once when its wrapper is deallocated.

#### Scenario: Evaluate branches concurrently

- **WHEN** concurrent tasks evaluate independent branches of one pipeline
- **THEN** each task receives its own valid output
- **AND** no task mutates the shared input pipeline

#### Scenario: Retain buffer-backed input safely

- **WHEN** an image is created from input bytes and the caller releases or
  mutates the original `Data`
- **THEN** the pipeline remains decodable because the native input retains its
  own bytes
