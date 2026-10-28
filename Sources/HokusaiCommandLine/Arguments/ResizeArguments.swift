import ArgumentParser
import Hokusai

/// Resize fit words accepted by `--fit`.
enum ResizeFitArgument: String, CaseInsensitiveArgument {
    case inside, outside, fill, cover, contain

    var fit: ResizeFit {
        switch self {
        case .inside: .inside
        case .outside: .outside
        case .fill: .fill
        case .cover: .cover
        case .contain: .contain
        }
    }
}

/// Resampling kernel words accepted by `--kernel`.
enum ResizeKernelArgument: String, CaseInsensitiveArgument {
    case nearest, linear, cubic, mitchell, lanczos2, lanczos3, mks2013, mks2021

    var kernel: ResizeKernel {
        switch self {
        case .nearest: .nearest
        case .linear: .linear
        case .cubic: .cubic
        case .mitchell: .mitchell
        case .lanczos2: .lanczos2
        case .lanczos3: .lanczos3
        case .mks2013: .mks2013
        case .mks2021: .mks2021
        }
    }
}

/// Thumbnail crop words accepted by `--crop`. `center` is accepted as a
/// spelling of `centre`, and `none` means fit inside without cropping.
enum CropStrategyArgument: String, CaseIterable, ExpressibleByArgument {
    case none, centre, attention, entropy

    init?(argument: String) {
        switch argument.lowercased() {
        case "center": self = .centre
        case let word: self.init(rawValue: word)
        }
    }

    /// The crop anchor, or nil when the thumbnail is not cropped.
    var position: ResizePosition? {
        switch self {
        case .none: nil
        case .centre: .center
        case .attention: .attention
        case .entropy: .entropy
        }
    }
}
