## ADDED Requirements

### Requirement: Preserve written semantics during planning

The library SHALL lower a pipeline's operations in the order they were
written and SHALL NOT reorder, merge, or drop them. It MAY skip an operation
only when it is a proven identity under Hokusai's documented semantics: a
rotation by an exact whole number of turns, or compositing no layers. It
SHALL NOT treat an operation as an identity because its parameters merely look
unchanged.

#### Scenario: Operations run in written order

- **WHEN** a caller writes `blur` then `resize`, or `resize` then `blur`
- **THEN** the operations are lowered in exactly that order
- **AND** the two orders produce different output

#### Scenario: Skip a whole-turn rotation

- **WHEN** a pipeline rotates by 360 degrees
- **THEN** the rotation is not applied
- **AND** the output is identical to the output of the unoptimised lowering

#### Scenario: Keep a partial rotation

- **WHEN** a pipeline rotates by an angle that is not a whole number of turns
- **THEN** the rotation is applied

### Requirement: Keep output choices out of the image plan

Output format and metadata choices SHALL be terminal configuration rather than
image operations, and the last choice SHALL win. A composite layer SHALL
contribute only its image operations.

#### Scenario: Last terminal configuration wins

- **WHEN** a caller selects PNG and then WebP output
- **THEN** the evaluated output is WebP
- **AND** the image operations are unchanged

### Requirement: Share work within one evaluation only

Within one terminal evaluation, a plan node reached by several consumers SHALL
be built once, so a source or layer used more than once is opened once. Sharing
SHALL be by plan identity, not by structural equality of independent values;
SHALL NOT apply to sources opened for sequential access; and SHALL NOT outlive
the evaluation. Hokusai SHALL NOT keep results between evaluations.

#### Scenario: A layer used twice is built once

- **WHEN** one pipeline value is used as two composite layers
- **THEN** its source is opened once in that evaluation
- **AND** the output is identical to the unoptimised lowering

#### Scenario: Independent values are not merged

- **WHEN** two separately created pipelines have identical source bytes
- **THEN** each source is opened separately

#### Scenario: Evaluations are independent

- **WHEN** the same pipeline is evaluated twice
- **THEN** each evaluation opens its source and reuses nothing from the other
