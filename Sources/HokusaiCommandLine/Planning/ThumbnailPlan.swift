import ArgumentParser
import Hokusai

/// What `thumbnail` asks of the public pipeline.
///
/// A thumbnail is not a separate operation: it is an optional `autoOrient()`
/// followed by an ordinary `resize`. Any source optimisation is the
/// evaluator's decision, as it is for every other resize.
struct ThumbnailPlan: Equatable {
    var width: Int
    var height: Int?
    var crop: CropStrategyArgument
    var autoOrient: Bool

    /// A crop needs a fully specified target rectangle.
    func validate() throws {
        if crop.position != nil && height == nil {
            throw ValidationError("--crop \(crop.rawValue) requires --height: a crop needs a fully specified target rectangle.")
        }
    }

    func apply(to source: Hokusai) throws -> Hokusai {
        let oriented = autoOrient ? source.autoOrient() : source
        return try oriented.resize(
            width: width, height: height,
            fit: crop.position == nil ? .inside : .cover,
            position: crop.position ?? .center)
    }
}
