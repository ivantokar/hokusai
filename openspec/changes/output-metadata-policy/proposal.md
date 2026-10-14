## Why

Output metadata was one boolean. `preserveMetadata()` kept everything,
`removeMetadata()` (the default) removed everything including the ICC profile
and orientation tag, which changes how an image displays, and encoders used
the legacy `strip` flag. #24 (roadmap #52, the release-critical slice) replaces
it with a typed policy, as #40 and #51 require.

## What Changes

- **BREAKING** `preserveMetadata()` and `removeMetadata()` are removed in
  favour of `metadataPolicy(_ MetadataPolicy)`: per-family `exif`, `icc`,
  `xmp`, `iptc`, `other`, `orientation`, `density`, each `.preserve` or
  `.remove`, with `.default`, `.preserveAll`, and `.removeAll`.
- **BREAKING (behavior)** The default removes EXIF, XMP, IPTC, and comments
  and keeps the ICC profile, orientation, and density.
- Encoders pass a `VipsForeignKeep` set instead of `strip`. Orientation and
  density are header fields `keep` cannot express, so they are handled on a
  private image copy: removing EXIF while keeping orientation retains a
  minimal EXIF block; removing orientation deletes the tag without rotating
  pixels; removing density stops the source's resolution being carried.
- The same lowering serves `data()` and `write(to:)`.
- CLI: no flag means the default policy; `--strip-metadata` means `.removeAll`.

Not done here: `stats()`, entropy, sharpness, dominant colour, and histograms
(the additive slice of #24, a separate change); ICC conversion or attachment
(colour management); a `normalize` orientation policy that rotates pixels.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `image-pipeline`: adds the output metadata requirement.

## Impact

- Public API: new `MetadataPolicy`; two methods removed.
- Output: bytes differ by default (profile, orientation, density now kept).
- CLI: default behavior changes as above.
