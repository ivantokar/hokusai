## ADDED Requirements

### Requirement: Enforce the supported native baseline

Hokusai SHALL build with Swift tools 6.0 or later in Swift 6 language mode and
SHALL be tested with both Swift 6.0 and Swift 6.4. Hokusai SHALL require
libvips 8.16 or later and Cairo 1.16 or later with PDF surface support, and
SHALL reject older native headers at compile time with a diagnostic that names
the required version. Codecs and features that depend on how libvips was built
SHALL NOT be implied by the package dependency graph.

#### Scenario: Build against an unsupported libvips

- **WHEN** a consumer compiles Hokusai against libvips 8.15 headers
- **THEN** compilation fails with an error stating that libvips 8.16 or later
  is required

#### Scenario: Build against the baseline

- **WHEN** a consumer compiles Hokusai with Swift 6.0, libvips 8.16, and
  Cairo 1.16
- **THEN** the library, CLI, and integration products build and the test
  suite passes
