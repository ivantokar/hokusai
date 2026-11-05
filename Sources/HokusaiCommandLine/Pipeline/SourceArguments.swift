import ArgumentParser
import Foundation
import Hokusai

/// How the source is read: `InputOptions.AccessMode`, by name.
enum AccessModeArgument: String, CaseInsensitiveArgument {
    case random, sequential
    var mode: InputOptions.AccessMode { self == .random ? .random : .sequential }
}

/// `InputOptions.DecodeFailureLevel`, by name.
enum DecodeFailureArgument: String, CaseInsensitiveArgument {
    case none, truncated, error, warning
    var level: InputOptions.DecodeFailureLevel {
        switch self {
        case .none: .none
        case .truncated: .truncated
        case .error: .error
        case .warning: .warning
        }
    }
}

/// The start of a pipeline: an image file, standard input, or generated text, with the options of
/// `Hokusai(url:options:)` or `Hokusai.text(_:layout:style:)`.
struct SourceArguments: ParsableArguments {
    @Argument(help: "Input image path, or - for standard input.")
    var input: String?

    @Option(help: "Start from this text instead of an image (`Hokusai.text`, plain content).")
    var text: String?

    @Option(help: "Start from this Pango markup instead of an image (`Hokusai.text`, markup content).")
    var markup: String?

    @OptionGroup(title: "Text source options (with --text or --markup)")
    var typography: TextStyleOptions

    @Option(help: "Zero-based page or frame to read (`InputOptions.page`).")
    var page: Int?

    @Option(help: "Access mode: random (default) or sequential (`InputOptions.access`).")
    var access = AccessModeArgument.random

    @Option(help: "When a decoder problem becomes an error: none, truncated, error or warning (`InputOptions.failOn`).")
    var failOn = DecodeFailureArgument.warning

    @Option(help: "Largest encoded input in bytes (`InputLimits.maxBytes`).")
    var maxBytes: Int?

    @Option(help: "Largest decoded input in pixels (`InputLimits.maxPixels`).")
    var maxPixels: Int?

    @Option(help: "Largest number of bands (`InputLimits.maxChannels`).")
    var maxChannels: Int?

    @Flag(help: "Revalidate the file against libvips' operation cache (`InputOptions.revalidate`).")
    var revalidate = false

    func validate() throws {
        let given = [input != nil, text != nil, markup != nil].filter { $0 }.count
        guard given == 1 else { throw ValidationError("give exactly one of an input path, --text or --markup") }
        if (text != nil || markup != nil), page != nil || maxBytes != nil || maxChannels != nil || revalidate || access != .random || failOn != .warning {
            throw ValidationError("--page, --access, --fail-on, --max-bytes, --max-channels and --revalidate read an image; they do not apply to --text")
        }
    }

    var inputOptions: InputOptions {
        var limits = InputLimits()
        if let maxBytes { limits.maxBytes = maxBytes }
        if let maxPixels { limits.maxPixels = maxPixels }
        if let maxChannels { limits.maxChannels = maxChannels }
        return InputOptions(access: access.mode, failOn: failOn.level, page: page, limits: limits, revalidate: revalidate)
    }

    func makeImage() throws -> Hokusai {
        if let text {
            return try Hokusai.text(.plain(text), layout: typography.layout, style: typography.style)
        }
        if let markup {
            return try Hokusai.text(.markup(markup), layout: typography.layout, style: typography.style)
        }
        guard let input else { throw ValidationError("no input") }
        if input == "-" {
            return try Hokusai(data: FileHandle.standardInput.readDataToEndOfFile(), options: inputOptions)
        }
        return try Hokusai(url: URL(fileURLWithPath: input), options: inputOptions)
    }
}
