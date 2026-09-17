# Command-Line Interface Specification

## Purpose

Define the first-party `hokusai` executable used to inspect, transform, and
benchmark images through the public Hokusai API. Its image-editing commands
use the immutable pipeline and asynchronous terminal output.

## Requirements

### Requirement: Provide operational subcommands

The executable SHALL provide `info`, `inspect`, `resize`, `thumbnail`,
`convert`, `rotate`, `crop`, and `text` subcommands. Each command SHALL accept
the documented input and output arguments and report errors from the public
library rather than bypassing it.

#### Scenario: Inspect an image

- **WHEN** an operator runs `hokusai inspect --input <path>` with a valid image
- **THEN** the command displays image dimensions, channels, alpha presence, and
  detected format

#### Scenario: Resize an image

- **WHEN** an operator supplies an input image, output path, and valid resize
  options
- **THEN** the command writes the transformed image to the output path

### Requirement: Generate CLI thumbnails with the pipeline API

The `thumbnail` subcommand SHALL load a file through `Hokusai(url:)`, apply
EXIF auto-orientation unless `--no-rotate` is supplied, and resize using
inside or cover fit according to the crop setting. It SHALL infer the output
format from the destination path. This command SHALL NOT claim the
shrink-on-load optimization of the legacy static thumbnail API.

#### Scenario: Make an oriented pipeline thumbnail

- **WHEN** an operator runs `hokusai thumbnail` without `--no-rotate`
- **THEN** the image is auto-oriented before resizing
- **AND** the output is written in the format inferred from its path

### Requirement: Report runtime information

The `info` subcommand SHALL initialize the public runtime and display the
Hokusai and libvips versions in human-readable output.

#### Scenario: Query installed runtime versions

- **WHEN** an operator runs `hokusai info`
- **THEN** the output includes both the Hokusai and libvips versions

### Requirement: Offer benchmark commands

The executable SHALL expose a benchmark pipeline command for WebP encoding,
optionally with Gaussian blur and a libvips-concurrency sweep, without changing
library behavior outside the command process.

#### Scenario: Run a pipeline benchmark

- **WHEN** an operator invokes the benchmark pipeline command with a valid
  image input
- **THEN** the command reports mean, median, P95, and operations-per-second
  measurements for the selected cases
