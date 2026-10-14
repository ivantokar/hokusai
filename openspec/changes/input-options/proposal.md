## Why

`InputOptions` rejected every non-default value as unsupported while the real
loader used a separate `LoadOptions`, so the public input policy was not the
one that ran. Decoder strictness was not applied at all, and nothing bounded
hostile inputs before expensive decoding. #21 (roadmap #52, Phase 2) makes
`InputOptions` the single, applied policy.

## What Changes

- **BREAKING** `InputOptions` = `access`, `failOn`, `page`, `limits`,
  `revalidate`. `failOn` gains `.truncated`, is passed to libvips, and its
  `.warning` default is enforced. `pages` is removed.
- **BREAKING** `LoadOptions` is removed (`AccessMode` moves into
  `InputOptions`); legacy static loaders take `InputOptions`. The deprecated
  `Hokusai(path:)` is removed.
- Single-page selection using the page count libvips reports, so no native
  error text is parsed: out of range is `invalidOption`, a non-zero page of a
  single-page format is `unsupported`.
- `InputLimits` (`maxBytes` 512 MiB, `maxPixels` 268,402,689, `maxChannels`
  8): bytes are checked before `Data` is copied and against file size; pixels
  and channels from the header, with overflow-safe arithmetic. Failures are
  `HokusaiError.resource` with kinds `encodedBytes`, `decodedPixels`,
  `channels`.
- `revalidate` bypasses libvips' operation cache for a file open.
- Decoder failures that surface while pixels are read are reported as
  `decode` labelled with the failing source. A pass-through probe on each
  opened source records that the source itself failed to produce pixels, so
  classification never reads libvips error text.
- Fix the `pixel.png` fixture's invalid IDAT checksum (the old loader ignored
  it; the enforced default does not); keep the bad file as a failOn fixture.

Deferred: page ranges, all-page loading, animation (#27); shrink-on-load (#20);
zero-copy NIO input (#45).

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `image-pipeline`: input acceptance, decoder policy, page selection, limits.

## Impact

- Public API: `InputOptions` reshaped; `LoadOptions`, `InputOptions.pages`,
  `Hokusai(path:)` removed; new `InputLimits`; `DecodeFailureLevel.truncated`.
- Behavior: inputs with decoder warnings now fail by default (`failOn: .none`
  restores the previous leniency).
- CLI and output formats: unchanged.
