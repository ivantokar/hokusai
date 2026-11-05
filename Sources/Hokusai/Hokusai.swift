import Foundation
import CVips

/// An immutable image-processing pipeline backed by libvips.
///
/// Create a value from encoded bytes or a local file, append transformations,
/// select an encoder, then evaluate it with ``data()`` or ``write(to:)``.
/// Assigning the value is a safe way to branch work because transformations
/// always return a new pipeline.
///
/// ```swift
/// let card = try Hokusai(url: photoURL)
///     .autoOrient()
///     .resize(width: 1200, height: 630, fit: .cover)
///
/// async let webp = card.webp(quality: 82).data()
/// async let png = card.png().data()
/// ```
///
/// Building a pipeline only records intent and validates options; it performs
/// no native work. The source is opened, transformed, and encoded when a
/// terminal method runs, on Hokusai's evaluation scheduler rather than Swift's
/// cooperative executor. Cancelling the calling task cancels a queued
/// evaluation or asks libvips to stop a running one; both throw
/// `CancellationError`. Decode failures and pixel-dependent errors (such as
/// extending to a smaller canvas) therefore surface from the terminal.
public struct Hokusai: Sendable {
    let plan: ImagePlan
    let terminal: TerminalConfig

    init(plan: ImagePlan, terminal: TerminalConfig = TerminalConfig()) {
        self.plan = plan
        self.terminal = terminal
    }

    // MARK: - Pipeline input

    /// Creates a pipeline from encoded image bytes.
    ///
    /// The bytes are retained (copy-on-write) until evaluation, so the caller
    /// may reuse or release its own `data` value. They are copied into native
    /// storage when the terminal method opens the source, and the content is
    /// not decoded here: invalid image bytes are reported by the terminal.
    /// Opening reads only the header and builds a lazy source; pixels are
    /// decoded as the pipeline needs them.
    ///
    /// - Throws: ``HokusaiError/invalidInput(reason:)`` for empty data,
    ///   ``HokusaiError/invalidOption(name:reason:)`` for invalid `options`,
    ///   and ``HokusaiError/resource(_:)`` when `data` exceeds
    ///   `options.limits.maxBytes`.
    ///
    /// ```swift
    /// let avatar = try Hokusai(data: upload)
    /// ```
    public init(data: Data, options: InputOptions = .init()) throws {
        try options.validate()
        guard !data.isEmpty else {
            throw HokusaiError.invalidInput(reason: "encoded data is empty")
        }
        try options.limits.checkEncodedBytes(data.count)
        self.init(plan: .source(.data(data, options)))
    }

    /// Creates a pipeline from a local file URL.
    ///
    /// Remote URLs are intentionally rejected: networking, timeouts, and
    /// request-size policy belong to the calling server. Read remote content
    /// into `Data` first when that is the desired application behavior. The
    /// file is opened when a terminal method runs, so a missing file or a file
    /// larger than `options.limits.maxBytes` is reported there.
    ///
    /// - Throws: ``HokusaiError/invalidInput(reason:)`` for a non-file URL and
    ///   ``HokusaiError/invalidOption(name:reason:)`` for invalid `options`.
    public init(url: URL, options: InputOptions = .init()) throws {
        guard url.isFileURL else {
            throw HokusaiError.invalidInput(reason: "only file URLs are supported; use init(data:) for in-memory input")
        }
        try options.validate()
        self.init(plan: .source(.file(url, options)))
    }

    /// Creates a pipeline from raw pixels the caller already holds.
    ///
    /// Use this when pixels come from a renderer, a camera buffer, a
    /// computer-vision step or a binary protocol rather than an encoded file.
    /// The layout is described by `format`: interleaved unsigned samples,
    /// colour first and alpha last (see ``RawPixelFormat``). Rows run top to
    /// bottom.
    ///
    /// The bytes are retained copy-on-write until evaluation and copied into
    /// native storage when a terminal method opens the source, so the caller
    /// may reuse its buffer at once. Nothing borrows caller memory across an
    /// `await`.
    ///
    /// - Parameters:
    ///   - data: The pixels. Exactly `rowStride × height` bytes; the padding
    ///     after the last row may be missing.
    ///   - width: Pixels per row, `1...Int32.max`.
    ///   - height: Number of rows, `1...Int32.max`.
    ///   - format: The channel layout and sample width.
    ///   - rowStride: Bytes between the starts of two rows. `nil` means
    ///     tightly packed (`width × format.bytesPerPixel`).
    ///   - premultiplied: Whether the colour channels were already multiplied
    ///     by alpha. They are divided out on load, so every later operation
    ///     sees straight alpha, as for an encoded source. Ignored for a format
    ///     without alpha.
    ///   - limits: Bounds on the image, checked before any native call.
    ///
    /// - Throws: ``HokusaiError/invalidOption(name:reason:)`` for a bad
    ///   dimension or stride, ``HokusaiError/invalidInput(reason:)`` when the
    ///   byte count does not match the geometry, and
    ///   ``HokusaiError/resource(_:)`` when a limit is exceeded.
    ///
    /// ```swift
    /// let frame = try Hokusai(raw: pixels, width: 640, height: 480, format: .rgba8)
    /// let thumbnail = try await frame.resize(width: 320).webp().data()
    /// ```
    public init(
        raw data: Data,
        width: Int,
        height: Int,
        format: RawPixelFormat,
        rowStride: Int? = nil,
        premultiplied: Bool = false,
        limits: InputLimits = InputLimits()
    ) throws {
        let source = try RawSource(
            data: data, width: width, height: height, format: format,
            rowStride: rowStride, premultiplied: premultiplied, limits: limits)
        self.init(plan: .source(.raw(source)))
    }

    /// Creates a pipeline from the raw pixels another pipeline produced.
    ///
    /// Equivalent to `init(raw:width:height:format:rowStride:premultiplied:limits:)`
    /// with the values `image` carries, so a ``RawImage`` round-trips.
    public init(raw image: RawImage, limits: InputLimits = InputLimits()) throws {
        try self.init(
            raw: image.data, width: image.width, height: image.height, format: image.format,
            rowStride: image.rowStride, premultiplied: image.premultiplied, limits: limits)
    }

    // MARK: - Pipeline transformations

    /// Applies the source EXIF orientation before later transformations.
    public func autoOrient() -> Self {
        appending(.autoOrient)
    }

    /// Resizes the pipeline using familiar fit and position semantics.
    ///
    /// Supplying one dimension preserves aspect ratio. With both dimensions,
    /// `fit` controls whether Hokusai crops, pads, stretches, or constrains
    /// the result. `position` affects cover crops and `background` affects
    /// contain padding.
    ///
    /// ```swift
    /// let thumbnail = try image.resize(
    ///     width: 400, height: 400, fit: .cover, position: .attention
    /// )
    /// ```
    public func resize(
        width: Int? = nil,
        height: Int? = nil,
        fit: ResizeFit = .cover,
        position: ResizePosition = .center,
        kernel: ResizeKernel = .lanczos3,
        withoutEnlargement: Bool = false,
        withoutReduction: Bool = false,
        background: Color = .transparent
    ) throws -> Self {
        guard width != nil || height != nil else {
            throw HokusaiError.invalidOption(name: "resize", reason: "specify width, height, or both")
        }
        try Self.validate(dimension: width, name: "width")
        try Self.validate(dimension: height, name: "height")
        _ = try background.rgba8()
        try kernel.requireAvailable()
        return appending(.resize(ResizeStep(
            width: width,
            height: height,
            fit: fit,
            position: position,
            kernel: kernel,
            withoutEnlargement: withoutEnlargement,
            withoutReduction: withoutReduction,
            background: background
        )))
    }

    /// Rotates the pipeline clockwise by a finite number of degrees.
    ///
    /// Use ``autoOrient()`` for camera orientation. This method is for an
    /// intentional visual rotation. Exact right angles are lossless; any other
    /// angle resamples with `interpolation` and fills exposed corners with
    /// `background`.
    public func rotate(by degrees: Double, background: Color = .transparent, interpolation: Interpolation = .bilinear) throws -> Self {
        guard degrees.isFinite else {
            throw HokusaiError.invalidOption(name: "degrees", reason: "must be finite")
        }
        _ = try background.rgba8()
        return appending(.rotate(degrees: degrees, background: background, interpolation: interpolation))
    }

    /// Mirrors the image vertically using familiar image-processing terminology.
    public func flip() -> Self { appending(.flip) }

    /// Mirrors the image horizontally using familiar image-processing terminology.
    public func flop() -> Self { appending(.flop) }

    /// Extracts a rectangle from the current image.
    ///
    /// Coordinates are measured from the current top-left corner, so calling
    /// this before or after ``resize(width:height:fit:position:kernel:withoutEnlargement:withoutReduction:background:)`` produces different results.
    public func extract(x: Int, y: Int, width: Int, height: Int) throws -> Self {
        try Self.validate(dimension: width, name: "width")
        try Self.validate(dimension: height, name: "height")
        for (name, value) in [("x", x), ("y", y)] {
            guard (0...maximumNativeCoordinate).contains(value) else {
                throw HokusaiError.invalidOption(name: name, reason: "must be in 0...\(maximumNativeCoordinate)")
            }
        }
        return appending(.extract(x: x, y: y, width: width, height: height))
    }

    /// Extends the canvas to an exact size using an anchored background.
    ///
    /// This operation can only add canvas. Use `resize` or `extract` when a
    /// requested size is smaller than the current image; that is detected
    /// when the pipeline is evaluated.
    public func extend(to size: ImageSize, anchor: Gravity = .center, background: Color = .transparent) throws -> Self {
        try extend(to: size, anchor: anchor, mode: .background(background))
    }

    /// Extends the canvas to an exact size, filling the new area according to `mode`.
    public func extend(to size: ImageSize, anchor: Gravity = .center, mode: ExtendMode) throws -> Self {
        try Self.validate(dimension: size.width, name: "width")
        try Self.validate(dimension: size.height, name: "height")
        _ = try mode.validated()
        return appending(.extend(to: size, anchor: anchor, mode: mode))
    }

    /// Adds padding around the image.
    ///
    /// Each side is a number of pixels, zero or greater. `mode` decides what
    /// fills the new pixels: a colour, or the image's own edge pixels copied,
    /// repeated or mirrored.
    ///
    /// ```swift
    /// let padded = try image.extend(top: 10, left: 10, bottom: 10, right: 10, mode: .mirror)
    /// ```
    public func extend(top: Int = 0, left: Int = 0, bottom: Int = 0, right: Int = 0, mode: ExtendMode = .background(.transparent)) throws -> Self {
        for (name, value) in [("top", top), ("left", left), ("bottom", bottom), ("right", right)] {
            guard (0...maximumNativeCoordinate).contains(value) else {
                throw HokusaiError.invalidOption(name: name, reason: "must be in 0...\(maximumNativeCoordinate)")
            }
        }
        _ = try mode.validated()
        return appending(.extendEdges(top: top, left: left, bottom: bottom, right: right, mode: mode))
    }

    /// Applies a 2×2 affine transform.
    ///
    /// The matrix maps input to output coordinates (`x' = a·x + b·y`,
    /// `y' = c·x + d·y`). Offsets are applied before (`inputOffset`) and after
    /// (`outputOffset`) the matrix, `outputArea` crops the result, and `edges`
    /// decides what fills pixels that map from outside the source.
    public func affine(
        _ matrix: AffineMatrix,
        inputOffset: AffineOffset = .zero,
        outputOffset: AffineOffset = .zero,
        outputArea: AffineArea? = nil,
        edges: ExtendMode = .background(.transparent),
        interpolation: Interpolation = .bilinear
    ) throws -> Self {
        let values = [matrix.a, matrix.b, matrix.c, matrix.d, inputOffset.x, inputOffset.y, outputOffset.x, outputOffset.y]
        guard values.allSatisfy({ $0.isFinite && abs($0) <= Double(maximumNativeCoordinate) * 10 }) else {
            throw HokusaiError.invalidOption(name: "matrix", reason: "values and offsets must be finite and of reasonable size")
        }
        guard matrix.a * matrix.d - matrix.b * matrix.c != 0 else {
            throw HokusaiError.invalidOption(name: "matrix", reason: "must be invertible (a·d − b·c must not be zero)")
        }
        if let area = outputArea {
            try Self.validate(dimension: area.width, name: "outputArea.width")
            try Self.validate(dimension: area.height, name: "outputArea.height")
            // Range checks, not abs(): abs(Int.min) is not representable and traps.
            let range = -maximumNativeCoordinate...maximumNativeCoordinate
            guard range.contains(area.x), range.contains(area.y),
                  area.width <= maximumNativeCoordinate, area.height <= maximumNativeCoordinate else {
                throw HokusaiError.invalidOption(name: "outputArea", reason: "must lie within \(maximumNativeCoordinate) pixels")
            }
        }
        _ = try edges.validated()
        return appending(.affine(AffineStep(
            matrix: matrix,
            inputOffset: inputOffset,
            outputOffset: outputOffset,
            outputArea: outputArea,
            edges: edges,
            interpolation: interpolation)))
    }

    /// Removes edges whose pixels are similar to the image background.
    ///
    /// `threshold` controls tolerance: lower values remove only nearly
    /// identical borders, while higher values remove a broader range. The
    /// scan runs when the pipeline is evaluated, not here.
    public func trim(threshold: Double = 10) throws -> Self {
        try trim(TrimOptions(threshold: threshold))
    }

    /// Removes the border around the content, with control over how the
    /// background is chosen and how much of it is kept.
    ///
    /// The background defaults to the top-left pixel. An image that is all
    /// background is left unchanged rather than cropped to nothing.
    public func trim(_ options: TrimOptions) throws -> Self {
        try options.validate()
        return appending(.trim(options))
    }

    /// Crops to `width` × `height` around the most interesting region, without resizing.
    ///
    /// A size larger than the image at that point in the pipeline is
    /// clamped to the image. Use ``resize(width:height:fit:position:kernel:withoutEnlargement:withoutReduction:background:)``
    /// with `.cover` to scale and crop in one step, and ``extract(x:y:width:height:)``
    /// for a fixed rectangle.
    public func smartCrop(width: Int, height: Int, strategy: SmartCropStrategy = .attention) throws -> Self {
        try Self.validate(dimension: width, name: "width")
        try Self.validate(dimension: height, name: "height")
        return appending(.smartCrop(width: width, height: height, strategy: strategy))
    }

    /// Applies a Gaussian blur.
    ///
    /// `blur()` is a mild blur (sigma 1) for the common case. `sigma` is the
    /// blur radius in pixels. `precision` and `minAmplitude` tune the Gaussian
    /// mask: a smaller `minAmplitude` gives a wider, more accurate mask. Pixels
    /// are weighted by alpha, so transparent areas do not bleed colour.
    public func blur(sigma: Double = 1, precision: BlurPrecision = .integer, minAmplitude: Double = 0.2) throws -> Self {
        guard sigma.isFinite, sigma > 0, sigma <= 10_000 else {
            throw HokusaiError.invalidOption(name: "sigma", reason: "must be a finite value above zero")
        }
        guard minAmplitude.isFinite, minAmplitude > 0, minAmplitude <= 10 else {
            throw HokusaiError.invalidOption(name: "minAmplitude", reason: "must be a finite value above zero and at most 10")
        }
        return appending(.blur(sigma: sigma, precision: precision, minAmplitude: minAmplitude))
    }

    /// Sharpens luminance with an unsharp mask. Alpha is untouched.
    public func sharpen(sigma: Double = 1) throws -> Self {
        try sharpen(SharpenOptions(sigma: sigma))
    }

    /// Sharpens luminance with explicit controls. Alpha is untouched.
    public func sharpen(_ options: SharpenOptions) throws -> Self {
        try options.validate()
        return appending(.sharpen(options))
    }

    /// Removes colour while keeping the image's RGB(A) layout.
    ///
    /// Luminance comes from libvips' sRGB conversion to black-and-white, which
    /// works in linear light. Alpha is preserved. To produce a single colour
    /// channel instead, use ``convert(to:)`` with ``ColorSpace/grayscale``.
    public func grayscale() -> Self {
        appending(.grayscale)
    }

    /// Maps luminance onto `color`: white becomes the tint and black stays black.
    ///
    /// The image is made grayscale first (see ``grayscale()``), so the result
    /// is RGB. Existing alpha is preserved; the colour's own opacity is ignored.
    public func tint(_ color: Color) throws -> Self {
        _ = try color.rgba8()
        return appending(.tint(color))
    }

    /// Stretches contrast between two luminance percentiles.
    ///
    /// The darkest `lower` percent and brightest `100 - upper` percent of
    /// pixels are clipped, and what remains is stretched to the full range.
    /// One linear map is applied to every colour band, so hue is kept and
    /// alpha is untouched. A flat image is returned unchanged. Requires an
    /// 8- or 16-bit image.
    public func normalize(lower: Double = 1, upper: Double = 99) throws -> Self {
        guard lower.isFinite, upper.isFinite, lower >= 0, upper <= 100, lower < upper else {
            throw HokusaiError.invalidOption(name: "percentiles", reason: "must satisfy 0 <= lower < upper <= 100")
        }
        return appending(.normalize(lower: lower, upper: upper))
    }

    /// Local contrast enhancement (CLAHE) on the lightness of an 8-bit or 16-bit image.
    ///
    /// Lightness is equalised in LAB and the colour is kept, so hues do not drift
    /// as they do when each of R, G and B is equalised on its own. Greyscale
    /// images are equalised directly, and alpha is left unchanged. Float images
    /// throw `unsupported`.
    ///
    /// `width` and `height` are the tile size in pixels and `maxSlope` limits
    /// how much contrast a tile may gain (0 disables the limit, 3 is a common
    /// choice). This is adaptive, not the global stretch of ``normalize(lower:upper:)``.
    public func clahe(width: Int = 8, height: Int = 8, maxSlope: Int = 3) throws -> Self {
        try Self.validate(dimension: width, name: "width")
        try Self.validate(dimension: height, name: "height")
        guard (0...100).contains(maxSlope) else {
            throw HokusaiError.invalidOption(name: "maxSlope", reason: "must be in 0...100")
        }
        return appending(.clahe(width: width, height: height, maxSlope: maxSlope))
    }

    /// Applies `out = in ^ (1 / value)` to the colour bands: values above 1
    /// brighten midtones. It runs exactly where it is written in the chain.
    public func gamma(_ value: Double = 2.2) throws -> Self {
        guard value.isFinite, value >= 0.1, value <= 10 else {
            throw HokusaiError.invalidOption(name: "gamma", reason: "must be a finite value from 0.1 to 10")
        }
        return appending(.gamma(value))
    }

    /// Inverts colours. Alpha is inverted too only when `alpha` is true.
    public func negate(alpha: Bool = false) -> Self {
        appending(.negate(alpha: alpha))
    }

    /// Replaces each pixel with the median of its `size` × `size` neighbourhood.
    public func median(size: Int = 3) throws -> Self {
        guard (1...101).contains(size) else {
            throw HokusaiError.invalidOption(name: "size", reason: "must be in 1...101")
        }
        return appending(.median(size: size))
    }

    // MARK: - Advanced filters

    /// Convolves the colour channels with a custom kernel. Alpha is kept.
    ///
    /// See ``ConvolutionKernel`` for the arithmetic. The result is limited to the sample range,
    /// and pixels near the border read the nearest edge pixel.
    ///
    /// ```swift
    /// let crisp = try image.convolve(ConvolutionKernel(width: 3, height: 3, values: [0, -1, 0, -1, 5, -1, 0, -1, 0]))
    /// ```
    public func convolve(_ kernel: ConvolutionKernel) -> Self {
        appending(.convolve(kernel))
    }

    /// Multiplies the colour channels by `multiply` and adds `add` (0...255 scale; 16-bit images
    /// scale it), limiting the result to the sample range. Alpha is kept.
    ///
    /// `linear(multiply: 1.2, add: -10)` raises contrast around the dark end; `linear(multiply: 1, add: 20)`
    /// brightens. For a different factor per channel, use ``recombine(_:)``.
    public func linear(multiply: Double = 1, add: Double = 0) throws -> Self {
        guard multiply.isFinite, (-1000...1000).contains(multiply) else {
            throw HokusaiError.invalidOption(name: "multiply", reason: "must be a finite value from -1000 to 1000")
        }
        guard add.isFinite, (-65535...65535).contains(add) else {
            throw HokusaiError.invalidOption(name: "add", reason: "must be a finite value from -65535 to 65535")
        }
        return appending(.linear(multiply: multiply, add: add))
    }

    /// Mixes the red, green and blue channels with a 3×3 matrix, for sepia and other colour
    /// transforms. The image is read as sRGB; alpha is kept. See ``ColorMatrix``.
    ///
    /// ```swift
    /// let warm = image.recombine(.sepia)
    /// ```
    public func recombine(_ matrix: ColorMatrix) -> Self {
        appending(.recombine(matrix))
    }

    /// Grows bright areas: each sample becomes the maximum of the `2 × radius + 1` square around it.
    ///
    /// It works on each colour channel separately, so on a black-and-white mask (see
    /// ``threshold(_:grayscale:)``) it widens the white. Alpha is kept.
    ///
    /// - Throws: ``HokusaiError/invalidOption(name:reason:)`` unless `radius` is in `1...50`.
    public func dilate(radius: Int = 1) throws -> Self {
        try Self.validate(radius: radius)
        return appending(.dilate(radius: radius))
    }

    /// Shrinks bright areas: each sample becomes the minimum of the `2 × radius + 1` square around it.
    /// The inverse of ``dilate(radius:)``; `erode` then `dilate` removes specks, `dilate` then
    /// `erode` closes small gaps. Alpha is kept.
    ///
    /// - Throws: ``HokusaiError/invalidOption(name:reason:)`` unless `radius` is in `1...50`.
    public func erode(radius: Int = 1) throws -> Self {
        try Self.validate(radius: radius)
        return appending(.erode(radius: radius))
    }

    /// Replaces the colour channels with the strength of the change in luminance (see ``EdgeDetector``).
    /// The result has one colour channel, the image's sample type and its alpha.
    ///
    /// - Throws: ``HokusaiError/invalidOption(name:reason:)`` for a Canny `sigma` outside `0.1...20`.
    public func edges(_ detector: EdgeDetector = .sobel) throws -> Self {
        if case .canny(let sigma) = detector {
            guard sigma.isFinite, (0.1...20).contains(sigma) else {
                throw HokusaiError.invalidOption(name: "sigma", reason: "must be a finite value from 0.1 to 20")
            }
        }
        return appending(.edges(detector))
    }

    /// Keeps one channel as a grey image, read in sRGB (a grey, CMYK or other source is converted first).
    ///
    /// A pipeline that asks for ``Channel/alpha`` of an image without alpha throws
    /// ``HokusaiError/invalidOption(name:reason:)`` from the terminal method.
    public func extractChannel(_ channel: Channel) -> Self {
        appending(.extractChannel(channel))
    }

    /// Uses the luminance of `mask` as this image's alpha channel: white keeps a pixel, black hides it.
    ///
    /// The mask is another pipeline and must come out the same size as this one (resize one of
    /// them if needed); a mismatch throws ``HokusaiError/invalidOption(name:reason:)`` from the
    /// terminal method. An existing alpha channel is replaced. Combine with
    /// ``extractChannel(_:)`` to move alpha from one image to another.
    public func withAlpha(from mask: Hokusai) -> Self {
        appending(.joinAlpha(mask.plan))
    }

    private static func validate(radius: Int) throws {
        guard (1...50).contains(radius) else {
            throw HokusaiError.invalidOption(name: "radius", reason: "must be in 1...50")
        }
    }

    /// Turns pixels at or above `level` (0...255) white and the rest black.
    ///
    /// With `grayscale` (the default) colour is first reduced to one luminance
    /// channel, so the result is a single-channel mask. Without it each colour
    /// band is thresholded on its own. Alpha is kept.
    public func threshold(_ level: Double = 128, grayscale: Bool = true) throws -> Self {
        guard level.isFinite, (0...255).contains(level) else {
            throw HokusaiError.invalidOption(name: "level", reason: "must be in 0...255")
        }
        return appending(.threshold(level: level, grayscale: grayscale))
    }

    /// Adjusts brightness and saturation by multiplication and hue by rotation.
    ///
    /// Works in LCH: `brightness` scales lightness, `saturation` scales chroma
    /// (both 1 for no change, 0 or more), and `hue` rotates by degrees.
    public func modulate(brightness: Double = 1, saturation: Double = 1, hue: Double = 0) throws -> Self {
        guard brightness.isFinite, brightness >= 0, brightness <= 100 else {
            throw HokusaiError.invalidOption(name: "brightness", reason: "must be a finite value from 0 to 100")
        }
        guard saturation.isFinite, saturation >= 0, saturation <= 100 else {
            throw HokusaiError.invalidOption(name: "saturation", reason: "must be a finite value from 0 to 100")
        }
        guard hue.isFinite, abs(hue) <= 3600 else {
            throw HokusaiError.invalidOption(name: "hue", reason: "must be a finite number of degrees")
        }
        return appending(.modulate(brightness: brightness, saturation: saturation, hue: hue))
    }

    /// Converts the pipeline to a supported output colour space.
    ///
    /// ``ColorSpace/grayscale`` produces a single colour channel (plus alpha if
    /// present); use ``grayscale()`` for a visual effect that keeps RGB.
    public func convert(to colorSpace: ColorSpace) throws -> Self {
        switch colorSpace {
        case .sRGB: appending(.convertToSRGB)
        case .grayscale: appending(.convertToGrayscale)
        }
    }

    /// Adds an alpha band of constant `opacity` (0...1) when there is none.
    /// An existing alpha band is left as it is.
    public func ensureAlpha(opacity: Double = 1) throws -> Self {
        guard opacity.isFinite, (0...1).contains(opacity) else {
            throw HokusaiError.invalidOption(name: "opacity", reason: "must be a finite value from 0 through 1")
        }
        return appending(.ensureAlpha(opacity: opacity))
    }

    /// Composites over a solid background colour and removes alpha.
    /// Does nothing when there is no alpha.
    public func flatten(background: Color = .white) throws -> Self {
        _ = try background.rgba8()
        return appending(.flatten(background: background))
    }

    /// Drops the alpha band without compositing, so the colour of fully
    /// transparent pixels shows. Use ``flatten(background:)`` to composite.
    /// Does nothing when there is no alpha.
    public func removeAlpha() -> Self {
        appending(.removeAlpha)
    }

    /// Composites layers over the pipeline in array order.
    ///
    /// Later layers draw over earlier layers. Each layer may reuse another
    /// pipeline, allowing a logo or watermark to be prepared once and applied
    /// to many base images. Only a layer's image transformations apply; its
    /// encoder and metadata settings are ignored, and it is never encoded to
    /// be composed. All layers are blended by one native operation.
    ///
    /// - Parameter space: The colour space layers are blended in.
    public func composite(_ layers: [CompositeLayer], space: CompositingSpace = .srgb) throws -> Self {
        let steps = try layers.map { layer in
            guard layer.opacity.isFinite, (0...1).contains(layer.opacity) else {
                throw HokusaiError.invalidOption(name: "opacity", reason: "must be a finite value from 0 through 1")
            }
            try layer.placement.validate()
            return LayerStep(plan: layer.source.plan, placement: layer.placement, blend: layer.blend, opacity: layer.opacity)
        }
        return appending(.composite(steps, space: space))
    }

    /// Renders text as a new pipeline.
    ///
    /// The result is an ordinary immutable pipeline: transform it, composite
    /// it, or encode it on its own. Text is rendered by libvips with Pango
    /// when a terminal method runs, so a build without text support reports
    /// ``HokusaiError/unsupported(feature:reason:)`` there, not here.
    ///
    /// ```swift
    /// let badge = try Hokusai.text("SALE", style: TextStyle(fontSize: 48, color: .white))
    /// ```
    ///
    /// - Throws: ``HokusaiError/invalidOption(name:reason:)`` for an empty
    ///   text, a size or spacing out of range, or a font that is a file path.
    public static func text(_ content: TextContent, layout: TextLayout = .natural, style: TextStyle = TextStyle()) throws -> Hokusai {
        let source = TextSource(content: content, layout: layout, style: style)
        try source.validate()
        return Hokusai(plan: .source(.text(source)))
    }

    /// Draws text onto the pipeline.
    ///
    /// Sugar for compositing ``text(_:layout:style:)`` with the same
    /// placement, clipping and blending rules as any other layer.
    public func drawText(
        _ content: TextContent,
        placement: Placement = .at(x: 0, y: 0),
        layout: TextLayout = .natural,
        style: TextStyle = TextStyle()
    ) throws -> Self {
        try composite([CompositeLayer(Hokusai.text(content, layout: layout, style: style), placement: placement)])
    }

    // MARK: - Output configuration

    /// Selects an output encoder for subsequent terminal operations.
    ///
    /// Selecting a second encoder replaces the first; no bytes are produced
    /// until ``data()`` or ``write(to:)`` is called.
    public func encode(using format: Encoder) throws -> Self {
        try Self.validate(output: format)
        var terminal = terminal
        terminal.encoder = format
        return Self(plan: plan, terminal: terminal)
    }

    /// Selects JPEG output with optional progressive encoding.
    ///
    /// Chroma subsampling and Huffman optimisation are in ``JPEGOptions``.
    public func jpeg(quality: Int = 80, progressive: Bool = false) throws -> Self {
        try encode(using: .jpeg(.init(quality: quality, progressive: progressive)))
    }

    /// Selects JPEG output from a full options value.
    public func jpeg(options: JPEGOptions) throws -> Self { try encode(using: .jpeg(options)) }

    /// Selects PNG output with a compression level from 0 through 9, and
    /// optional Adam7 interlacing.
    public func png(compressionLevel: Int = 6, interlaced: Bool = false) throws -> Self {
        try encode(using: .png(.init(compressionLevel: compressionLevel, interlaced: interlaced)))
    }

    /// Selects PNG output from a full options value, including palette mode.
    public func png(options: PNGOptions) throws -> Self { try encode(using: .png(options)) }

    /// Selects WebP output.
    ///
    /// `effort` trades CPU time for compression efficiency; `lossless` changes
    /// the encoder mode rather than merely increasing quality.
    public func webp(quality: Int = 80, effort: Int = 4, lossless: Bool = false) throws -> Self {
        try encode(using: .webp(.init(quality: quality, effort: effort, lossless: lossless)))
    }

    /// Selects WebP output from a full options value.
    public func webp(options: WebPOptions) throws -> Self { try encode(using: .webp(options)) }

    /// Selects AVIF output.
    public func avif(quality: Int = 50, effort: Int = 4, lossless: Bool = false) throws -> Self {
        try encode(using: .avif(.init(quality: quality, effort: effort, lossless: lossless)))
    }

    /// Selects AVIF output from a full options value. The codec is always AV1.
    public func avif(options: AVIFOptions) throws -> Self { try encode(using: .avif(options)) }

    /// Selects HEIF output with an explicit codec (HEVC by default, as in `.heic`).
    ///
    /// Whether the codec is available depends on the libvips build; check
    /// ``RuntimeCapabilities/canEncode(_:)-(HEIFCompression)``. It is reported
    /// when the pipeline is evaluated.
    public func heif(compression: HEIFCompression = .hevc, quality: Int = 50, lossless: Bool = false) throws -> Self {
        try encode(using: .heif(.init(compression: compression, quality: quality, lossless: lossless)))
    }

    /// Selects HEIF output from a full options value.
    public func heif(options: HEIFOptions) throws -> Self { try encode(using: .heif(options)) }

    /// Selects TIFF output with the given compression.
    public func tiff(compression: TIFFCompression = .none, quality: Int = 75) throws -> Self {
        try encode(using: .tiff(.init(compression: compression, quality: quality)))
    }

    /// Selects TIFF output from a full options value, including tiling and BigTIFF.
    public func tiff(options: TIFFOptions) throws -> Self { try encode(using: .tiff(options)) }

    /// Selects still GIF output. Animation is not part of this encoder.
    public func gif(options: GIFOptions = GIFOptions()) throws -> Self { try encode(using: .gif(options)) }

    /// Configures a one-page Cairo PDF document from the current image pipeline.
    ///
    /// The resulting PDF contains rasterized pipeline output. It is suitable
    /// for image reports but does not preserve selectable vector text.
    public func pdf(
        pageSize: PDFPageSize = .image(),
        margins: PDFMargins = .none,
        anchor: Gravity = .center,
        background: Color? = nil,
        maxEffectiveDPI: Double? = nil,
        metadata: PDFDocumentMetadata? = nil
    ) throws -> Self {
        try encode(using: .pdf(PDFOptions(
            pageSize: pageSize, margins: margins, anchor: anchor,
            background: background, maxEffectiveDPI: maxEffectiveDPI, metadata: metadata)))
    }

    /// Chooses which embedded metadata the encoded output keeps.
    ///
    /// The default removes EXIF, XMP, IPTC and comments while keeping the ICC
    /// profile, orientation, and density. This is terminal configuration: it
    /// does not change pixels, the last call wins, and nothing is read from the
    /// source until a terminal evaluates the pipeline. See ``MetadataPolicy``.
    public func metadataPolicy(_ policy: MetadataPolicy) -> Self {
        var terminal = terminal
        terminal.metadataPolicy = policy
        return Self(plan: plan, terminal: terminal)
    }

    /// Inspects the root source of this pipeline and returns what it reported.
    ///
    /// The result describes the **source**, not the transformed pipeline:
    /// `image.metadata()` and `image.resize(width: 400).metadata()` are equal,
    /// and a composite pipeline reports only its base source. No operation is
    /// lowered and no pixels are decoded; opening reads the header, so
    /// problems that only appear while decoding pixels are not reported here.
    /// Use ``OutputInfo`` for what a pipeline produces.
    ///
    /// `options` given when the pipeline was created apply: the selected
    /// `page`, the input limits, and the access mode. Inspection runs on
    /// Hokusai's evaluation scheduler, off Swift's cooperative executor, and
    /// is cancelled with the calling task.
    ///
    /// - Throws: ``HokusaiError/io(url:operation:reason:)`` for a missing or
    ///   unreadable file, ``HokusaiError/decode(_:)`` for a source libvips
    ///   cannot open, and ``HokusaiError/resource(_:)`` when an input limit is
    ///   exceeded.
    public func metadata() async throws -> ImageMetadata {
        let source = plan.chain.source
        return try await EvaluationScheduler.shared.run { context in
            try Evaluator.inspect(source, context: context)
        }
    }

    /// The format the selected encoder will produce, or `nil` before one is chosen.
    ///
    /// It is known without evaluating anything, so a server can set a
    /// `Content-Type` header (``ImageFormat/mimeType``) before streaming starts.
    /// It always agrees with ``OutputInfo/format`` of the evaluated result.
    public var outputFormat: ImageFormat? { terminal.encoder?.imageFormat }

    /// Evaluates and encodes the pipeline on Hokusai's evaluation scheduler.
    ///
    /// Call an encoder method first. The returned ``Output`` includes both the
    /// owned bytes and the actual encoded dimensions, format, and byte count.
    public func data() async throws -> Output {
        guard let format = terminal.encoder else {
            throw HokusaiError.invalidOption(name: "output format", reason: "call jpeg(), png(), webp(), avif(), pdf(), or encode(using:) before data()")
        }
        let plan = plan, terminal = terminal
        return try await EvaluationScheduler.shared.run { context in
            try Evaluator.encode(plan, terminal, as: format, context: context)
        }
    }

    /// Evaluates the pipeline and returns raw pixels instead of an encoded image.
    ///
    /// The result is described completely by the returned ``RawImage``: its
    /// dimensions, channel layout, sample width, row stride and alpha
    /// convention. Rows are tightly packed. Nothing is encoded, so no metadata
    /// is kept and no encoder may be selected on this pipeline.
    ///
    /// The image is converted to `format` first. Colour is converted to sRGB
    /// (or to grey for a grey format) by libvips' colour-space conversion;
    /// embedded ICC profiles are not applied. A grey source gets its channel
    /// repeated for an RGB format, and a colour source is reduced to
    /// luminance for a grey format. Converting between 8 and 16 bits scales
    /// the range, so full white stays full white.
    ///
    /// - Parameters:
    ///   - format: The layout to return. Defaults to ``RawPixelFormat/rgba8``.
    ///   - premultiplied: Return colour channels multiplied by alpha. Ignored
    ///     for a format without alpha.
    ///   - background: What transparent pixels are composited over when
    ///     `format` has no alpha channel. Ignored for a format with alpha.
    ///
    /// - Throws: ``HokusaiError/invalidOption(name:reason:)`` when an encoder
    ///   was selected, plus any error from the pipeline itself.
    ///
    /// ```swift
    /// let frame = try await image.resize(width: 320).raw(.rgb8, background: .white)
    /// frame.data.count == frame.rowStride * frame.height
    /// ```
    public func raw(
        _ format: RawPixelFormat = .rgba8,
        premultiplied: Bool = false,
        background: Color = .white
    ) async throws -> RawImage {
        guard terminal.encoder == nil else {
            throw HokusaiError.invalidOption(name: "raw", reason: "an encoder is selected; raw output has no encoder, so use data() for an encoded image")
        }
        _ = try background.rgba8()
        let plan = plan
        return try await EvaluationScheduler.shared.run { context in
            try Evaluator.raw(plan, as: format, premultiplied: premultiplied, background: background, context: context)
        }
    }

    /// Evaluates and writes the pipeline to a local file URL.
    ///
    /// If no encoder was selected, the file extension determines the format.
    /// Parent directories are not created automatically.
    @discardableResult
    public func write(to url: URL) async throws -> OutputInfo {
        guard url.isFileURL else {
            throw HokusaiError.invalidOption(name: "url", reason: "write(to:) accepts only file URLs")
        }
        let format = try terminal.encoder ?? Self.outputFormat(from: url)
        let plan = plan, terminal = terminal
        return try await EvaluationScheduler.shared.run { context in
            try Evaluator.write(plan, terminal, as: format, to: url, context: context)
        }
    }

    /// Evaluates the pipeline and hands the encoded bytes to `consume` as they are produced.
    ///
    /// Call an encoder method first: there is no file name to infer a format
    /// from. Encoder options and metadata policy are those of ``data()`` and
    /// ``write(to:)``.
    ///
    /// The bytes arrive as owned chunks of `chunkSize` (the last may be
    /// smaller; none are empty). The next chunk is not requested until
    /// `consume` has returned for the previous one, and the encoder waits when
    /// the consumer falls behind, so at most `chunkSize × 4` bytes of encoded
    /// output are held in the hand-off, however large the image. Slow
    /// responses therefore slow encoding down instead of growing the queue.
    /// That bounds encoded output only: the memory libvips and the codecs use
    /// to decode and transform the image is not bounded by `chunkSize`. TIFF
    /// cannot be written forward-only, so its complete output is encoded in
    /// memory first and then streamed in chunks.
    ///
    /// If `consume` throws, encoding stops and that error is thrown. If the
    /// calling task is cancelled, encoding stops and `CancellationError` is
    /// thrown. In either case, or if encoding fails after output began, the
    /// consumer has already received a partial stream and must discard it.
    ///
    /// - Parameters:
    ///   - chunkSize: Target size of each chunk, in `1...67_108_864` bytes.
    ///   - consume: Receives each chunk in order.
    /// - Returns: The format, dimensions and total byte count of the stream.
    @discardableResult
    public func writeChunks(
        chunkSize: Int = 64 * 1024,
        _ consume: (Data) async throws -> Void
    ) async throws -> OutputInfo {
        guard let format = terminal.encoder else {
            throw HokusaiError.invalidOption(name: "output format", reason: "call jpeg(), png(), webp(), avif(), pdf(), or encode(using:) before writeChunks()")
        }
        guard (1...ChunkQueue.maxChunkSize).contains(chunkSize) else {
            throw HokusaiError.invalidOption(name: "chunkSize", reason: "must be in 1...\(ChunkQueue.maxChunkSize)")
        }
        let plan = plan, terminal = terminal
        let queue = ChunkQueue(chunkSize: chunkSize)
        return try await withTaskCancellationHandler {
            // Any producer failure ends the stream, including a rejection by the
            // scheduler's admission, which happens before the work closure runs.
            async let produced: OutputInfo = {
                do {
                    return try await EvaluationScheduler.shared.run { context in
                        try Evaluator.stream(plan, terminal, as: format, into: queue, context: context)
                    }
                } catch {
                    queue.abort()
                    throw error
                }
            }()
            do {
                while let chunk = await queue.next() { try await consume(chunk) }
            } catch {
                queue.abort()
                _ = try? await produced
                throw error
            }
            let info = try await produced
            // Cancellation after the producer finished discards chunks the
            // consumer has not received; that is not a complete stream.
            if queue.didDiscardOutput { throw CancellationError() }
            return info
        } onCancel: {
            queue.abort()
        }
    }

    // MARK: - Pipeline helpers

    private func appending(_ operation: ImageOperation) -> Self {
        Self(plan: plan.appending(operation), terminal: terminal)
    }

    private static func validate(dimension: Int?, name: String) throws {
        guard let dimension else { return }
        guard dimension > 0, Int32(exactly: dimension) != nil else {
            throw HokusaiError.invalidOption(name: name, reason: "must be in 1...\(Int32.max)")
        }
    }

    private static func validate(output: Encoder) throws {
        func range(_ name: String, _ value: Int, _ bounds: ClosedRange<Int>) throws {
            guard bounds.contains(value) else {
                throw HokusaiError.invalidOption(name: name, reason: "must be in \(bounds.lowerBound)...\(bounds.upperBound)")
            }
        }
        func unit(_ name: String, _ value: Double) throws {
            guard value.isFinite, (0...1).contains(value) else { throw HokusaiError.invalidOption(name: name, reason: "must be in 0...1") }
        }
        switch output.kind {
        case .jpeg(let options):
            try range("quality", options.quality, 1...100)
        case .png(let options):
            try range("compressionLevel", options.compressionLevel, 0...9)
            if let palette = options.palette {
                try range("palette.quality", palette.quality, 0...100)
                try unit("palette.dither", palette.dither)
                try range("palette.effort", palette.effort, 1...10)
                try range("palette.bitDepth", palette.bitDepth, 1...8)
                guard [1, 2, 4, 8].contains(palette.bitDepth) else {
                    throw HokusaiError.invalidOption(name: "palette.bitDepth", reason: "must be 1, 2, 4 or 8")
                }
            }
        case .webp(let options):
            try range("quality", options.quality, 1...100)
            try range("effort", options.effort, 0...6)
            try range("alphaQuality", options.alphaQuality, 0...100)
        case .avif(let options):
            try range("quality", options.quality, 1...100)
            try range("effort", options.effort, 0...9)
        case .heif(let options):
            try range("quality", options.quality, 1...100)
            try range("effort", options.effort, 0...9)
        case .tiff(let options):
            try range("quality", options.quality, 1...100)
            if let tiling = options.tiling {
                try range("tiling.width", tiling.width, 16...32768)
                try range("tiling.height", tiling.height, 16...32768)
                guard tiling.width % 16 == 0, tiling.height % 16 == 0 else {
                    throw HokusaiError.invalidOption(name: "tiling", reason: "width and height must be multiples of 16")
                }
            }
        case .gif(let options):
            try options.validate()
        case .pdf(let options):
            try PDFLayout.validate(options)
        }
    }

    private static func outputFormat(from url: URL) throws -> Encoder {
        guard let format = ImageFormat.from(fileExtension: url.pathExtension) else {
            throw HokusaiError.invalidOption(name: "output URL", reason: "use a supported image extension or select an encoder")
        }
        switch format {
        case .jpeg: return .jpeg()
        case .png: return .png()
        case .webp: return .webp()
        case .avif: return .avif()
        case .heif: return .heif()
        case .tiff: return .tiff()
        case .gif: return .gif()
        case .pdf: return .pdf()
        case .svg: throw HokusaiError.unsupported(feature: "writing svg", reason: "SVG is an input format, not an encoder")
        }
    }

    // MARK: - Lifecycle Management

    /// Initialize the libvips runtime.
    ///
    /// libvips is process-scoped: it is initialized at most once and remains
    /// available until the process exits. Repeated and concurrent calls are
    /// safe. Every native entry point initializes the runtime automatically,
    /// so an explicit call is only needed to surface initialization failures
    /// at application startup.
    ///
    /// - Throws: ``HokusaiError/runtime(_:)`` if libvips could
    ///   not be initialized. The failure is final for the process.
    public static func initialize() throws {
        try VipsRuntime.ensureInitialized()
    }

    // MARK: - Runtime configuration

    /// Sets process-wide runtime configuration. Call once, at startup.
    ///
    /// Configuration freezes at the first ``initialize()``, ``capabilities()``,
    /// or terminal evaluation; building pipelines does not freeze it.
    ///
    /// - Throws: ``HokusaiError/invalidOption(name:reason:)`` for invalid
    ///   values, or ``HokusaiError/runtime(_:)`` when the configuration is
    ///   already frozen or was already set.
    public static func configure(_ configuration: RuntimeConfiguration) throws {
        try VipsRuntime.configure(configuration)
    }

    /// Reports which formats and features the linked native libraries support.
    ///
    /// Discovery initializes libvips (freezing configuration) and runs once;
    /// the result is cached and safe to share.
    ///
    /// - Throws: ``HokusaiError/runtime(_:)`` if libvips could
    ///   not be initialized.
    public static func capabilities() throws -> RuntimeCapabilities {
        try VipsRuntime.capabilities()
    }

    /// A snapshot of the evaluation scheduler and effective settings.
    ///
    /// Reading it never initializes libvips or freezes configuration.
    public static var runtimeStatus: RuntimeStatus {
        let (configuration, isFrozen, isInitialized) = VipsRuntime.configurationSnapshot
        let scheduler = isFrozen ? EvaluationScheduler.shared : nil
        return RuntimeStatus(
            configuration: configuration,
            isConfigurationFrozen: isFrozen,
            queuedEvaluations: scheduler?.queued ?? 0,
            activeEvaluations: scheduler?.active ?? 0,
            maxConcurrentEvaluations: scheduler?.limit
                ?? configuration.maxConcurrentEvaluations.fixedValue
                ?? EvaluationScheduler.automaticLimit,
            vipsConcurrency: isInitialized ? VipsRuntime.vipsConcurrency : nil
        )
    }
}
