## ADDED Requirements

### Requirement: Measure the pixels of the current pipeline

`stats()` SHALL evaluate the current pipeline and return per-channel
statistics, opacity, luminance entropy, sharpness, and a dominant colour, all
measured on 8-bit pixels after conversion to sRGB or grey. It SHALL describe
the transformed pipeline and not the source, SHALL NOT encode output or consume
the pipeline, and SHALL run on the evaluation scheduler and be cancelled with
its task. Entropy and sharpness SHALL ignore alpha. Failures SHALL use the same
typed errors as an encoding terminal.

#### Scenario: Statistics follow the pipeline

- **WHEN** a caller measures a cropped pipeline
- **THEN** the statistics describe the crop and differ from the source's

#### Scenario: Known distributions

- **WHEN** a caller measures an image that is half black and half white
- **THEN** the luminance entropy is one bit
- **AND** a single flat tone has entropy and sharpness of zero

#### Scenario: Sharp versus blurred

- **WHEN** the same image is measured sharp and then blurred
- **THEN** the sharp image has the higher sharpness

#### Scenario: Opacity

- **WHEN** an image has an alpha band with a transparent pixel
- **THEN** it is not reported as opaque
- **AND** an image with no alpha band is opaque

#### Scenario: Cancellation

- **WHEN** a running analysis is cancelled
- **THEN** it throws `CancellationError`
