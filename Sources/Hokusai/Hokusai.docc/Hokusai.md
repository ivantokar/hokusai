# Hokusai

Build an immutable image-processing pipeline, then evaluate it asynchronously.

```swift
let output = try await Hokusai(data: upload)
    .autoOrient()
    .resize(width: 1200, height: 630, fit: .cover, position: .attention)
    .webp(quality: 82)
    .data()
```

`Hokusai` values are immutable and `Sendable`. Assigning a pipeline creates a
safe branch of the same source recipe; transforms return a new value. Blocking
libvips evaluation happens only in ``Hokusai/data()`` and
``Hokusai/write(to:)``, never on Swift's cooperative executor.

## Topics

### Creating a pipeline

- ``Hokusai/init(data:options:)``
- ``Hokusai/init(url:options:)``
- ``InputOptions``

### Transforming an image

- ``Hokusai/resize(width:height:fit:position:kernel:withoutEnlargement:withoutReduction:background:)``
- ``Hokusai/autoOrient()``
- ``Hokusai/composite(_:)``
- ``Hokusai/blur(sigma:)``

### Encoding and output

- ``Hokusai/jpeg(quality:progressive:)``
- ``Hokusai/png(compressionLevel:progressive:)``
- ``Hokusai/webp(quality:effort:lossless:)``
- ``Hokusai/data()``
- ``Hokusai/write(to:)``
