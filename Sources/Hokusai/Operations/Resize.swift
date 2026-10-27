import Foundation
import CVips

extension HokusaiImage {
    /// Returns a resized legacy image handle using libvips.
    ///
    /// The method first computes a proportional intermediate size. `cover`
    /// crops that result, while `contain` embeds it in the requested canvas.
    /// This mirrors the geometry rules used by the 1.0 pipeline API.
    public func resize(width: Int? = nil, height: Int? = nil, options: ResizeOptions = ResizeOptions()) throws -> HokusaiImage {
        HokusaiImage(native: try native().resize(width: width, height: height, options: options))
    }

    /// Stretches the image to exact dimensions without preserving aspect ratio.
    public func resize(width: Int, height: Int) throws -> HokusaiImage {
        var options = ResizeOptions()
        options.fit = .fill
        return try resize(width: width, height: height, options: options)
    }

    /// Resizes to fit inside optional bounds without cropping.
    public func resizeToFit(width: Int? = nil, height: Int? = nil) throws -> HokusaiImage {
        var options = ResizeOptions()
        options.fit = .inside
        return try resize(width: width, height: height, options: options)
    }

    /// Resizes to cover bounds and crops overflow at the selected position.
    public func resizeToCover(width: Int, height: Int, position: Position = .center) throws -> HokusaiImage {
        var options = ResizeOptions()
        options.fit = .cover
        options.position = position
        return try resize(width: width, height: height, options: options)
    }
}

extension NativeImage {
    /// Resizes for the legacy image handle.
    ///
    /// Explicit `width`/`height` take precedence over those stored in
    /// `options`. The work is done by the modern geometry in
    /// `NativeGeometry.swift`; this only translates the legacy vocabulary.
    func resize(width: Int?, height: Int?, options: ResizeOptions) throws -> NativeImage {
        try resize(
            width: width ?? options.width,
            height: height ?? options.height,
            fit: options.fit,
            position: options.position.pipeline,
            kernel: options.kernel.pipeline,
            withoutEnlargement: options.withoutEnlargement,
            withoutReduction: options.withoutReduction,
            background: options.background ?? [0, 0, 0, 255])
    }
}

extension Position {
    /// The pipeline placement with the same meaning.
    var pipeline: ResizePosition {
        switch self {
        case .center: .center
        case .top: .north
        case .bottom: .south
        case .left: .west
        case .right: .east
        case .topLeft: .northWest
        case .topRight: .northEast
        case .bottomLeft: .southWest
        case .bottomRight: .southEast
        case .entropy: .entropy
        case .attention: .attention
        }
    }
}

extension Kernel {
    /// The pipeline kernel with the same meaning.
    var pipeline: ResizeKernel {
        switch self {
        case .nearest: .nearest
        case .linear: .linear
        case .cubic: .cubic
        case .mitchell: .mitchell
        case .lanczos2: .lanczos2
        case .lanczos3: .lanczos3
        }
    }
}
