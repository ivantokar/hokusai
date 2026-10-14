## ADDED Requirements

### Requirement: Control output metadata with a typed policy

Encoded output SHALL keep or remove each metadata family (EXIF, ICC profile,
XMP, IPTC, other, orientation, density) as a `MetadataPolicy` says, configured
on the terminal and not as an image operation. The default policy SHALL remove
EXIF, XMP, IPTC, and other metadata while keeping the ICC profile, orientation,
and density. A family the target format cannot carry SHALL be absent from its
output.

#### Scenario: Default policy

- **WHEN** a caller encodes a JPEG that carries EXIF with a description, XMP,
  IPTC, an ICC profile, and orientation 6, with the default policy
- **THEN** the output keeps the ICC profile, the orientation, and the density
- **AND** it carries no XMP, no IPTC, and no EXIF description

#### Scenario: Preserve everything

- **WHEN** the caller selects `.preserveAll`
- **THEN** the EXIF description, XMP, IPTC, ICC profile, and orientation are all present

#### Scenario: Remove everything without touching pixels

- **WHEN** the caller selects `.removeAll` for an image with orientation 6
- **THEN** no EXIF, XMP, IPTC, profile, or orientation tag remains
- **AND** the stored width and height are unchanged

#### Scenario: Control one family

- **WHEN** a caller preserves only IPTC, or removes only the ICC profile
- **THEN** only that family differs from the default

### Requirement: Keep metadata policy free of side effects

Retention SHALL be applied identically to `data()` and `write(to:)`. Removing
orientation SHALL delete the tag without rotating pixels, and retaining an ICC
profile SHALL NOT convert colours.

#### Scenario: Same result for both sinks

- **WHEN** a caller evaluates a pipeline with a policy through `data()` and
  `write(to:)`
- **THEN** both outputs are identical
