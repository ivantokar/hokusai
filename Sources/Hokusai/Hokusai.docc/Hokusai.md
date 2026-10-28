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

## Pages and animation

A pipeline reads one page or frame, chosen with ``InputOptions/page``, and
every encoder writes one image. Page count describes structure and is never
treated as animation: ``ImageMetadata/animation`` exists only when the source
carries frame timing. Transforming and re-encoding an animated GIF or WebP
produces its selected frame, not an animation.

## Topics

### Creating a pipeline

- ``Hokusai/init(data:options:)``
- ``Hokusai/init(url:options:)``
- ``InputOptions``
- ``InputOptions/AccessMode``
- ``InputOptions/DecodeFailureLevel``
- ``InputLimits``

### Transforming an image

- ``Hokusai/resize(width:height:fit:position:kernel:withoutEnlargement:withoutReduction:background:)``
- ``Hokusai/autoOrient()``
- ``Hokusai/composite(_:)``
- ``Hokusai/blur(sigma:)``

### Encoding and output

- ``Hokusai/jpeg(quality:progressive:)``
- ``Hokusai/png(compressionLevel:interlaced:)``
- ``Hokusai/webp(quality:effort:lossless:)``
- ``Hokusai/encode(using:)``
- ``Encoder``
- ``Hokusai/metadataPolicy(_:)``
- ``Hokusai/data()``
- ``Hokusai/write(to:)``
