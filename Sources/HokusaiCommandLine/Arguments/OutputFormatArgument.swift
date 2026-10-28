import ArgumentParser
import Foundation
import Hokusai

/// Output formats the CLI can write: the public encoder set.
///
/// SVG is deliberately absent because it is an input-only format. `jpg`,
/// `tif` and `heic` are accepted as spellings of `jpeg`, `tiff` and `heif`,
/// both for `--format` and for output filename extensions.
enum OutputFormatArgument: String, CaseIterable, ExpressibleByArgument {
    case jpeg, png, webp, avif, heif, tiff, gif, pdf

    init?(argument: String) {
        switch argument.lowercased() {
        case "jpg": self = .jpeg
        case "tif": self = .tiff
        case "heic": self = .heif
        case let word: self.init(rawValue: word)
        }
    }

    /// The format a filename extension names, if it names one.
    init?(pathExtensionOf path: String) {
        let ext = URL(fileURLWithPath: path).pathExtension
        guard !ext.isEmpty else { return nil }
        self.init(argument: ext)
    }

    var format: ImageFormat {
        switch self {
        case .jpeg: .jpeg
        case .png: .png
        case .webp: .webp
        case .avif: .avif
        case .heif: .heif
        case .tiff: .tiff
        case .gif: .gif
        case .pdf: .pdf
        }
    }
}
