import Foundation
import CVips

/// The most times a tiled layer may repeat; keeps a one-pixel tile on a very
/// large base from asking libvips for an absurd array.
private let maximumTileCount = 10_000_000

// MARK: - Placement arithmetic

extension Placement {
    /// Rejects coordinates whose arithmetic could overflow a native coordinate.
    func validate() throws {
        let values: [Int]
        switch self {
        case .at(let x, let y): values = [x, y]
        case .gravity(_, let offsetX, let offsetY): values = [offsetX, offsetY]
        case .tile: values = []
        }
        let allowed = -maximumNativeCoordinate...maximumNativeCoordinate
        guard values.allSatisfy({ allowed.contains($0) }) else {
            throw HokusaiError.invalidOption(
                name: "placement", reason: "coordinates must be within ±\(maximumNativeCoordinate) pixels")
        }
    }

    /// The top-left corner of a `layer`-sized rectangle on a `base`-sized one.
    ///
    /// Inputs are bounded (see ``validate()`` and the image dimension limits),
    /// so none of this can overflow.
    func origin(layer: (width: Int, height: Int), base: (width: Int, height: Int)) -> (x: Int, y: Int) {
        switch self {
        case .at(let x, let y):
            return (x, y)
        case .gravity(let gravity, let offsetX, let offsetY):
            return gravity.origin(layer: layer, base: base, offsetX: offsetX, offsetY: offsetY)
        case .tile(let gravity):
            return gravity.origin(layer: layer, base: base, offsetX: 0, offsetY: 0)
        }
    }
}

private extension Gravity {
    enum Edge { case start, middle, end }

    var horizontal: Edge {
        switch self {
        case .west, .northWest, .southWest: .start
        case .east, .northEast, .southEast: .end
        case .center, .north, .south: .middle
        }
    }

    var vertical: Edge {
        switch self {
        case .north, .northWest, .northEast: .start
        case .south, .southWest, .southEast: .end
        case .center, .east, .west: .middle
        }
    }

    func origin(
        layer: (width: Int, height: Int), base: (width: Int, height: Int), offsetX: Int, offsetY: Int
    ) -> (x: Int, y: Int) {
        func axis(_ edge: Edge, layer: Int, base: Int, offset: Int) -> Int {
            switch edge {
            case .start: offset
            case .middle: (base - layer) / 2 + offset
            case .end: base - layer - offset
            }
        }
        return (
            axis(horizontal, layer: layer.width, base: base.width, offset: offsetX),
            axis(vertical, layer: layer.height, base: base.height, offset: offsetY)
        )
    }
}

// MARK: - Layers

/// One resolved composite layer: its pipeline already built to a native image.
struct NativeLayer {
    let image: NativeImage
    let placement: Placement
    let blend: BlendMode
    let opacity: Double
}

extension BlendMode {
    /// The libvips `VipsBlendMode` value.
    var vipsRawValue: Int32 { Int32(vipsValue.rawValue) }

    private var vipsValue: VipsBlendMode {
        switch self {
        case .clear: VIPS_BLEND_MODE_CLEAR
        case .source: VIPS_BLEND_MODE_SOURCE
        case .over: VIPS_BLEND_MODE_OVER
        case .in: VIPS_BLEND_MODE_IN
        case .out: VIPS_BLEND_MODE_OUT
        case .atop: VIPS_BLEND_MODE_ATOP
        case .destination: VIPS_BLEND_MODE_DEST
        case .destinationOver: VIPS_BLEND_MODE_DEST_OVER
        case .destinationIn: VIPS_BLEND_MODE_DEST_IN
        case .destinationOut: VIPS_BLEND_MODE_DEST_OUT
        case .destinationAtop: VIPS_BLEND_MODE_DEST_ATOP
        case .xor: VIPS_BLEND_MODE_XOR
        case .add: VIPS_BLEND_MODE_ADD
        case .saturate: VIPS_BLEND_MODE_SATURATE
        case .multiply: VIPS_BLEND_MODE_MULTIPLY
        case .screen: VIPS_BLEND_MODE_SCREEN
        case .overlay: VIPS_BLEND_MODE_OVERLAY
        case .darken: VIPS_BLEND_MODE_DARKEN
        case .lighten: VIPS_BLEND_MODE_LIGHTEN
        case .colorDodge: VIPS_BLEND_MODE_COLOUR_DODGE
        case .colorBurn: VIPS_BLEND_MODE_COLOUR_BURN
        case .hardLight: VIPS_BLEND_MODE_HARD_LIGHT
        case .softLight: VIPS_BLEND_MODE_SOFT_LIGHT
        case .difference: VIPS_BLEND_MODE_DIFFERENCE
        case .exclusion: VIPS_BLEND_MODE_EXCLUSION
        }
    }
}

extension CompositingSpace {
    fileprivate var interpretation: VipsInterpretation {
        switch self {
        case .srgb: VIPS_INTERPRETATION_sRGB
        case .linear: VIPS_INTERPRETATION_scRGB
        }
    }
}

extension NativeImage {
    /// Blends `layers` over this image with a single libvips array composite.
    ///
    /// libvips converts every input to the compositing space and adds a solid
    /// alpha where one is missing, so no layer is forced to 8-bit RGBA first.
    /// Per-layer preparation (opacity, tiling) is lazy and happens before the
    /// call, which keeps all layers eligible for the one native operation.
    func composite(_ layers: [NativeLayer], space: CompositingSpace) throws -> NativeImage {
        guard !layers.isEmpty else { return self }
        let base = (width: width, height: height)

        var images = [self]
        var modes: [Int32] = []
        var xs: [Int32] = []
        var ys: [Int32] = []
        for layer in layers {
            let faded = try layer.image.scalingAlpha(by: layer.opacity)
            let placed: NativeImage
            let origin: (x: Int, y: Int)
            if case .tile(let gravity) = layer.placement {
                (placed, origin) = try faded.tiled(over: base, gravity: gravity)
            } else {
                placed = faded
                origin = layer.placement.origin(layer: (faded.width, faded.height), base: base)
            }
            images.append(placed)
            modes.append(layer.blend.vipsRawValue)
            xs.append(clamped(origin.x))
            ys.append(clamped(origin.y))
        }

        var pointers: [UnsafeMutablePointer<CVips.VipsImage>?] = images.map { $0.pointer }
        let space = space.interpretation
        let result = try Self.producing({ output in
            pointers.withUnsafeMutableBufferPointer { buffer in
                swift_vips_composite_array(buffer.baseAddress, output, Int32(buffer.count), &modes, xs, ys, space)
            }
        }, failure: { .nativeTransform("composite") })
        withExtendedLifetime(images) {}
        guard space == VIPS_INTERPRETATION_scRGB else { return result }
        return try result.leavingLinearLight(matching: self)
    }

    /// Converts a linear-light (scRGB, float) result back to `original`'s
    /// bit depth in the matching display space, so linear blending changes
    /// the mix and nothing else about the output.
    fileprivate func leavingLinearLight(matching original: NativeImage) throws -> NativeImage {
        let format = original.bandFormat
        let wide = format == Int32(VIPS_FORMAT_USHORT.rawValue)
        let target = wide ? VIPS_INTERPRETATION_RGB16 : VIPS_INTERPRETATION_sRGB
        let display = try applying("composite") { swift_vips_colourspace($0, $1, target) }
        return try display.castRounded(to: wide || format == Int32(VIPS_FORMAT_UCHAR.rawValue) ? format : display.bandFormat, operation: "composite")
    }

    /// Multiplies the alpha band by `opacity`, adding one first if needed.
    ///
    /// The band format is kept, so 16-bit and float layers stay that way, and
    /// the colour bands are untouched. Opacity 1 returns the layer as is.
    func scalingAlpha(by opacity: Double) throws -> NativeImage {
        guard opacity < 1 else { return self }
        let original = bandFormat
        let withAlpha = try ensureAlpha(opacity: 1)
        var scale = [Double](repeating: 1, count: withAlpha.bands)
        scale[withAlpha.bands - 1] = opacity
        let offset = [Double](repeating: 0, count: withAlpha.bands)
        let scaled = try withAlpha.applying("composite") {
            swift_vips_linear_array($0, $1, scale, offset, Int32(scale.count))
        }
        return try scaled.castRounded(to: original, operation: "composite")
    }

    /// Repeats the image to cover `base`, with one tile aligned to `gravity`.
    ///
    /// Returns the repeated image and the origin to composite it at. The
    /// repeat is lazy, so only the visible part is ever computed.
    fileprivate func tiled(
        over base: (width: Int, height: Int), gravity: Gravity
    ) throws -> (NativeImage, (x: Int, y: Int)) {
        let tile = (width: width, height: height)
        let anchor = Placement.tile(gravity: gravity).origin(layer: tile, base: base)

        /// Where the first tile starts and how many fit to the far edge.
        func span(anchor: Int, tile: Int, base: Int) -> (start: Int, count: Int) {
            let phase = ((anchor % tile) + tile) % tile
            let start = phase == 0 ? 0 : phase - tile
            return (start, (base - start + tile - 1) / tile)
        }
        let columns = span(anchor: anchor.x, tile: tile.width, base: base.width)
        let rows = span(anchor: anchor.y, tile: tile.height, base: base.height)
        guard columns.count <= maximumTileCount / rows.count else {
            throw HokusaiError.invalidOption(
                name: "placement", reason: "tile would repeat the layer more than \(maximumTileCount) times")
        }
        let repeated = try applying("composite") { swift_vips_replicate($0, $1, Int32(columns.count), Int32(rows.count)) }
        return (repeated, (columns.start, rows.start))
    }
}

private func clamped(_ value: Int) -> Int32 {
    Int32(max(-Int(Int32.max), min(Int(Int32.max), value)))
}
