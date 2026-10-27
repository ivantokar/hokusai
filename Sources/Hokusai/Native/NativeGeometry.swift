import Foundation
import CVips

/// The largest canvas dimension libvips accepts (`VIPS_MAX_COORD`).
let maximumNativeCoordinate = 10_000_000

// MARK: - Native vocabulary

extension ResizeKernel {
    /// Throws `unsupported` when this libvips build cannot provide the kernel.
    ///
    /// Cheap and pixel-free, so a pipeline can reject it while it is built.
    func requireAvailable() throws {
        _ = try vipsKernel()
    }

    fileprivate func vipsKernel() throws -> VipsKernel {
        switch self {
        case .nearest: return VIPS_KERNEL_NEAREST
        case .linear: return VIPS_KERNEL_LINEAR
        case .cubic: return VIPS_KERNEL_CUBIC
        case .mitchell: return VIPS_KERNEL_MITCHELL
        case .lanczos2: return VIPS_KERNEL_LANCZOS2
        case .lanczos3: return VIPS_KERNEL_LANCZOS3
        case .mks2013, .mks2021:
            let raw = swift_vips_kernel_mks(self == .mks2013 ? 0 : 1)
            guard raw >= 0 else {
                throw HokusaiError.unsupported(
                    feature: "\(self == .mks2013 ? "mks2013" : "mks2021") resize kernel",
                    reason: "requires libvips 8.17 or newer")
            }
            return VipsKernel(rawValue: UInt32(raw))
        }
    }
}

extension ExtendMode {
    /// Checks the mode's colour without touching libvips.
    func validated() throws -> ExtendMode {
        _ = try resolved()
        return self
    }

    /// The native extend value and, for ``background(_:)``, the RGBA fill.
    func resolved() throws -> (extend: VipsExtend, background: [Double]?) {
        switch self {
        case .background(let color): return (VIPS_EXTEND_BACKGROUND, try color.rgba8())
        case .copy: return (VIPS_EXTEND_COPY, nil)
        case .repeat: return (VIPS_EXTEND_REPEAT, nil)
        case .mirror: return (VIPS_EXTEND_MIRROR, nil)
        }
    }
}

/// An owned native interpolator, released when it goes out of scope.
private final class NativeInterpolator {
    let pointer: UnsafeMutablePointer<VipsInterpolate>

    init(_ interpolation: Interpolation, operation: String) throws {
        guard let pointer = swift_vips_interpolate_new(interpolation.rawValue) else {
            throw HokusaiError.unsupported(feature: "\(interpolation.rawValue) interpolation", reason: "not available in this libvips build")
        }
        self.pointer = pointer
    }

    deinit { g_object_unref(pointer) }
}

extension NativeImage {
    /// Passes an owned native RGBA array to `body` and releases it afterwards.
    static func withNativeArray<T>(
        _ values: [Double],
        operation: String,
        _ body: (UnsafeMutablePointer<VipsArrayDouble>) throws -> T
    ) throws -> T {
        let area = values.withUnsafeBufferPointer { swift_vips_array_double_new($0.baseAddress, Int32($0.count)) }
        guard let area else {
            throw HokusaiError.allocationFailed(operation)
        }
        defer { vips_area_unref(UnsafeMutablePointer(mutating: UnsafeRawPointer(area).assumingMemoryBound(to: VipsArea.self))) }
        return try body(area)
    }
}

// MARK: - Fill colours

extension NativeImage {
    /// An 8-bit RGBA colour expressed in this image's own bands.
    ///
    /// libvips needs a fill with one value per band: luminance for grey,
    /// grey plus alpha, RGB, or RGBA. 16-bit images use the 0...65535 range.
    func fill(_ rgba: [Double]) -> [Double] {
        guard rgba.count == 4 else { return rgba }
        let luminance = 0.2126 * rgba[0] + 0.7152 * rgba[1] + 0.0722 * rgba[2]
        let values: [Double]
        switch bands {
        case 1: values = [luminance]
        case 2: values = [luminance, rgba[3]]
        case 3: values = [rgba[0], rgba[1], rgba[2]]
        default: values = rgba + Array(repeating: 255, count: bands - 4)
        }
        let interpretation = swift_vips_image_get_interpretation(pointer)
        let sixteenBit = interpretation == VIPS_INTERPRETATION_RGB16.rawValue || interpretation == VIPS_INTERPRETATION_GREY16.rawValue
        return sixteenBit ? values.map { $0 * 257 } : values
    }
}

// MARK: - Resize

extension NativeImage {
    /// Resizes with a proportional resample, then crops (`cover`) or pads
    /// (`contain`) to the requested box.
    ///
    /// Sizes are computed in Swift so libvips receives one coherent, positive
    /// target. `background` is 8-bit RGBA and only affects `contain`.
    ///
    /// `reference` is the size the written pipeline sees when this image is a
    /// decoder-shrunk stand-in for it (see ``Evaluator``): the target size is
    /// derived from `reference`, so the result has exactly the dimensions the
    /// unshrunk image would give, and only the remaining scale is resampled.
    func resize(
        width: Int?,
        height: Int?,
        fit: ResizeFit,
        position: ResizePosition,
        kernel: ResizeKernel,
        withoutEnlargement: Bool,
        withoutReduction: Bool,
        background: [Double],
        reference: (width: Int, height: Int)? = nil
    ) throws -> NativeImage {
        guard width != nil || height != nil else {
            throw HokusaiError.invalidOption(name: "resize", reason: "specify width, height, or both")
        }

        let (finalWidth, finalHeight) = Self.proportionalSize(
            current: reference ?? (self.width, self.height),
            target: (width, height),
            fit: fit,
            withoutEnlargement: withoutEnlargement,
            withoutReduction: withoutReduction)

        let vipsKernel = try kernel.vipsKernel()
        let hscale = Double(finalWidth) / Double(self.width)
        let vscale = Double(finalHeight) / Double(self.height)
        let resized = try applying("resize") { swift_vips_resize($0, $1, hscale, vscale, vipsKernel) }

        // Cover and contain need a second step after proportional resampling.
        guard let width, let height else { return resized }
        switch fit {
        case .cover:
            return try resized.coverCrop(width: width, height: height, position: position)
        case .contain:
            let (x, y) = position.canvasAnchor.offset(
                imageWidth: resized.width, imageHeight: resized.height, canvasWidth: width, canvasHeight: height)
            return try resized.embed(
                x: x, y: y, width: width, height: height, extend: VIPS_EXTEND_BACKGROUND, background: background, operation: "resize")
        default:
            return resized
        }
    }

    /// The proportional intermediate size before crop or canvas padding.
    ///
    /// Each side is at least one pixel so extreme aspect ratios never ask
    /// libvips for an empty image.
    static func proportionalSize(
        current: (width: Int, height: Int),
        target: (width: Int?, height: Int?),
        fit: ResizeFit,
        withoutEnlargement: Bool,
        withoutReduction: Bool
    ) -> (width: Int, height: Int) {
        let aspectRatio = Double(current.width) / Double(current.height)
        var finalWidth: Int
        var finalHeight: Int

        switch fit {
        case .fill:
            finalWidth = target.width ?? current.width
            finalHeight = target.height ?? current.height

        case .inside, .contain, .outside, .cover:
            let covering = fit == .outside || fit == .cover
            if let w = target.width, let h = target.height {
                // Largest size inside both bounds, or smallest covering both.
                let targetAspect = Double(w) / Double(h)
                if (aspectRatio > targetAspect) != covering {
                    finalWidth = w
                    finalHeight = Int(Double(w) / aspectRatio)
                } else {
                    finalHeight = h
                    finalWidth = Int(Double(h) * aspectRatio)
                }
            } else if let w = target.width {
                finalWidth = w
                finalHeight = Int(Double(w) / aspectRatio)
            } else {
                // Callers guarantee at least one dimension.
                let h = target.height ?? current.height
                finalHeight = h
                finalWidth = Int(Double(h) * aspectRatio)
            }
        }

        if withoutEnlargement, finalWidth > current.width || finalHeight > current.height {
            finalWidth = current.width
            finalHeight = current.height
        }
        if withoutReduction, finalWidth < current.width || finalHeight < current.height {
            finalWidth = current.width
            finalHeight = current.height
        }
        return (max(1, finalWidth), max(1, finalHeight))
    }

    /// A target-sized crop using an anchor or libvips smart crop.
    func coverCrop(width: Int, height: Int, position: ResizePosition) throws -> NativeImage {
        // Avoid native work when the geometry already matches.
        if self.width == width && self.height == height {
            return self
        }
        switch position {
        case .attention:
            return try applying("smart crop") { swift_vips_smartcrop($0, $1, Int32(width), Int32(height), VIPS_INTERESTING_ATTENTION) }
        case .entropy:
            return try applying("smart crop") { swift_vips_smartcrop($0, $1, Int32(width), Int32(height), VIPS_INTERESTING_ENTROPY) }
        default:
            let anchor = position.canvasAnchor
            // The crop box sits inside the image, so offsets are clamped at zero.
            let offset = anchor.offset(imageWidth: width, imageHeight: height, canvasWidth: self.width, canvasHeight: self.height)
            return try crop(left: max(0, offset.x), top: max(0, offset.y), width: width, height: height)
        }
    }
}

extension ResizePosition {
    /// The compass anchor for fixed placements. Content-aware strategies have
    /// no anchor of their own and centre.
    var canvasAnchor: Gravity {
        switch self {
        case .center, .attention, .entropy: .center
        case .north: .north
        case .south: .south
        case .east: .east
        case .west: .west
        case .northWest: .northWest
        case .northEast: .northEast
        case .southWest: .southWest
        case .southEast: .southEast
        }
    }
}

// MARK: - Canvas

extension NativeImage {
    /// Extends to an exact canvas size. The canvas can only grow.
    func extend(to size: ImageSize, anchor: Gravity, mode: ExtendMode) throws -> NativeImage {
        guard size.width >= width, size.height >= height else {
            throw HokusaiError.invalidOption(name: "size", reason: "extend cannot reduce an image; use resize or extract")
        }
        let offset = anchor.offset(imageWidth: width, imageHeight: height, canvasWidth: size.width, canvasHeight: size.height)
        return try embed(x: offset.x, y: offset.y, width: size.width, height: size.height, mode: mode, operation: "extend")
    }

    /// Adds `top`, `left`, `bottom` and `right` pixels around the image.
    func extend(top: Int, left: Int, bottom: Int, right: Int, mode: ExtendMode) throws -> NativeImage {
        for (name, value) in [("top", top), ("left", left), ("bottom", bottom), ("right", right)] where value < 0 {
            throw HokusaiError.invalidOption(name: name, reason: "must be zero or greater")
        }
        return try embed(
            x: left, y: top, width: width + left + right, height: height + top + bottom, mode: mode, operation: "extend")
    }

    private func embed(x: Int, y: Int, width: Int, height: Int, mode: ExtendMode, operation: String) throws -> NativeImage {
        let (extend, background) = try mode.resolved()
        return try embed(x: x, y: y, width: width, height: height, extend: extend, background: background, operation: operation)
    }

    private func embed(
        x: Int, y: Int, width: Int, height: Int,
        extend: VipsExtend, background: [Double]?, operation: String
    ) throws -> NativeImage {
        // Checked before any native call so an oversized canvas is a typed
        // option error rather than a failure deep in libvips.
        guard width <= maximumNativeCoordinate, height <= maximumNativeCoordinate else {
            throw HokusaiError.invalidOption(name: "size", reason: "canvas dimensions must not exceed \(maximumNativeCoordinate) pixels")
        }
        guard let background else {
            return try applying(operation) {
                swift_vips_embed_extend($0, $1, Int32(x), Int32(y), Int32(width), Int32(height), extend, nil)
            }
        }
        return try Self.withNativeArray(fill(background), operation: operation) { area in
            try applying(operation) {
                swift_vips_embed_extend($0, $1, Int32(x), Int32(y), Int32(width), Int32(height), extend, area)
            }
        }
    }
}

// MARK: - Rotation, orientation, affine

extension NativeImage {
    /// Rotates clockwise by `degrees`.
    ///
    /// Exact right angles use the lossless `vips_rot`; every other angle
    /// resamples with `vips_rotate` and fills exposed corners with `background`.
    func rotate(degrees: Double, background: [Double], interpolation: Interpolation) throws -> NativeImage {
        var turn = degrees.truncatingRemainder(dividingBy: 360)
        if turn < 0 { turn += 360 }

        let angle: VipsAngle
        switch turn {
        case 0: return self
        case 90: angle = VIPS_ANGLE_D90
        case 180: angle = VIPS_ANGLE_D180
        case 270: angle = VIPS_ANGLE_D270
        default:
            let interpolator = try NativeInterpolator(interpolation, operation: "rotate")
            return try Self.withNativeArray(fill(background), operation: "rotate") { area in
                try applying("rotate") { swift_vips_rotate($0, $1, degrees, area, interpolator.pointer) }
            }
        }
        return try applying("rotate") { swift_vips_rot($0, $1, angle) }
    }

    /// Mirrors the image vertically (`flip`) or horizontally (`flop`).
    func mirrored(_ direction: VipsDirection, operation: String) throws -> NativeImage {
        try applying(operation) { swift_vips_flip($0, $1, direction) }
    }

    /// Applies the source EXIF orientation and clears the orientation tag so
    /// it cannot be applied twice.
    func autoOrient() throws -> NativeImage {
        try applying("auto orient") { swift_vips_autorot($0, $1) }
    }

    func affine(_ step: AffineStep) throws -> NativeImage {
        let (extend, background) = try step.edges.resolved()
        let interpolator = try NativeInterpolator(step.interpolation, operation: "affine")
        let matrix = step.matrix
        let area = step.outputArea.map { [Int32($0.x), Int32($0.y), Int32($0.width), Int32($0.height)] }
        return try Self.withNativeArray(background.map(fill) ?? [0], operation: "affine") { backgroundArray in
            try applying("affine") { input, output in
                let call = { (oarea: UnsafePointer<Int32>?) -> Int32 in
                    swift_vips_affine(
                        input, output, matrix.a, matrix.b, matrix.c, matrix.d,
                        interpolator.pointer, extend, backgroundArray,
                        step.inputOffset.x, step.inputOffset.y, step.outputOffset.x, step.outputOffset.y, oarea)
                }
                guard let area else { return call(nil) }
                return area.withUnsafeBufferPointer { call($0.baseAddress) }
            }
        }
    }
}

// MARK: - Pixel access

extension NativeImage {
    /// Reads one pixel's bands. Evaluates only that pixel's neighbourhood.
    func pixel(x: Int, y: Int) throws -> [Double] {
        var values = [Double](repeating: 0, count: max(bands, 1))
        let count = values.withUnsafeMutableBufferPointer {
            swift_vips_getpoint(pointer, Int32(x), Int32(y), $0.baseAddress, Int32($0.count))
        }
        guard count >= 0 else {
            throw HokusaiError.nativeTransform("read pixel")
        }
        return Array(values.prefix(Int(count)))
    }
}
