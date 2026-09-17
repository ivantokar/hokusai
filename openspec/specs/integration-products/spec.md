# Integration Products Specification

## Purpose

Define compatibility behavior for Hokusai's optional SwiftNIO bridge and
temporary 0.x migration product.

## Requirements

### Requirement: Bridge SwiftNIO byte buffers safely

The `HokusaiNIO` product SHALL create pipelines from a readable `ByteBuffer`
and expose `Output.byteBuffer`. Both conversions SHALL copy bytes so the
source or returned buffer can be independently reused or released.

#### Scenario: Construct a pipeline from a byte buffer

- **WHEN** a caller creates `Hokusai(buffer:)` from readable encoded bytes
- **THEN** the resulting pipeline can be evaluated after the caller reuses the
  source buffer

#### Scenario: Receive encoded output as a byte buffer

- **WHEN** a caller reads `Output.byteBuffer`
- **THEN** it contains the same readable bytes as `Output.data`

### Requirement: Re-export the compatibility surface

The `HokusaiLegacy` product SHALL re-export `Hokusai` so existing 0.x consumers
can keep importing a compatibility product while migrating. New code SHALL use
the immutable `Hokusai` pipeline and its asynchronous terminals. The legacy
surface remains available from the main module at this revision; its detailed
behavior is specified separately in `legacy-image-api`.

#### Scenario: Import compatibility product

- **WHEN** an existing consumer imports `HokusaiLegacy`
- **THEN** it can access the maintained legacy adapter surface while migrating
  to the primary product
