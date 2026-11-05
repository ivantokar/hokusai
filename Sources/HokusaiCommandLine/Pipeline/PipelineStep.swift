import ArgumentParser
import Foundation
import Hokusai

/// One step of a `hokusai run` pipeline: the CLI form of one public API method.
///
/// A step is named after the method it calls (`resize`, `auto-orient`, `webp`) and carries exactly
/// the options of that method, with the method's own defaults. Nothing is shared between steps, so
/// an option can never be accepted by a step that would ignore it.
protocol PipelineStep: ParsableArguments {
    static var name: String { get }
    static var summary: String { get }
    func apply(to image: Hokusai) throws -> Hokusai
}

enum PipelineSteps {
    /// The groups are the order of `hokusai run --help`.
    static let groups: [(title: String, steps: [any PipelineStep.Type])] = [
        ("Geometry", [
            AutoOrientStep.self, ResizeStep.self, RotateStep.self, FlipStep.self, FlopStep.self, ExtractStep.self,
            ExtendStep.self, AffineStep.self, TrimStep.self, SmartCropStep.self,
        ]),
        ("Effects", [
            BlurStep.self, SharpenStep.self, GrayscaleStep.self, TintStep.self, NormalizeStep.self, ClaheStep.self,
            GammaStep.self, NegateStep.self, MedianStep.self, ThresholdStep.self, ModulateStep.self,
        ]),
        ("Advanced filters", [
            ConvolveStep.self, LinearStep.self, RecombineStep.self, DilateStep.self, ErodeStep.self, EdgesStep.self,
            ExtractChannelStep.self, WithAlphaStep.self,
        ]),
        ("Colour and alpha", [ConvertToStep.self, EnsureAlphaStep.self, FlattenStep.self, RemoveAlphaStep.self]),
        ("Composition and text", [CompositeStep.self, DrawTextStep.self]),
        ("Output encoders", [
            JPEGStep.self, PNGStep.self, WebPStep.self, AVIFStep.self, HEIFStep.self, TIFFStep.self, GIFStep.self, PDFStep.self,
            MetadataPolicyStep.self,
        ]),
    ]

    static let all: [any PipelineStep.Type] = groups.flatMap(\.steps)
    static let names: Set<String> = Set(all.map { $0.name })

    static func type(named name: String) -> (any PipelineStep.Type)? { all.first { $0.name == name } }
}

/// What `hokusai run` was asked to do.
struct PipelineRequest {
    var source: SourceArguments
    var steps: [any PipelineStep]
    var output: String?
    var json: Bool
    var verbose: Bool
}

/// Splits a command line into the source, the steps in the order written, and the run-level options.
///
/// `-o`, `--output`, `--json` and `--verbose` apply to the whole run and may stand anywhere. What is
/// left starts with the source (an input path or `--text`) and continues with steps. A step ends at
/// the next word that names a step, but only when what came before parses as that step's options, so
/// `tiff --compression jpeg` is read as an option value and not as the start of a `jpeg` step.
enum PipelineParser {
    static func parse(_ arguments: [String]) throws -> PipelineRequest {
        var rest: [String] = []
        var output: String?
        var json = false
        var verbose = false
        var index = 0
        while index < arguments.count {
            let word = arguments[index]
            switch word {
            case "-o", "--output":
                guard index + 1 < arguments.count else { throw CommandFailure(message: "\(word) needs a path (use - for standard output)") }
                output = arguments[index + 1]
                index += 2
            case "--json":
                json = true
                index += 1
            case "-v", "--verbose":
                verbose = true
                index += 1
            default:
                if word.hasPrefix("--output=") { output = String(word.dropFirst("--output=".count)) } else { rest.append(word) }
                index += 1
            }
        }

        let (source, next) = try segment(SourceArguments.self, label: "the input", in: rest, from: 0, skipping: 0)
        var steps: [any PipelineStep] = []
        var position = next
        while position < rest.count {
            guard let type = PipelineSteps.type(named: rest[position]) else {
                throw CommandFailure(message: "'\(rest[position])' is not a step. Run `hokusai run --help` to list them.")
            }
            let (step, after) = try parseStep(type, in: rest, at: position)
            steps.append(step)
            position = after
        }
        return PipelineRequest(source: source, steps: steps, output: output, json: json, verbose: verbose)
    }

    private static func parseStep<S: PipelineStep>(_ type: S.Type, in words: [String], at start: Int) throws -> (any PipelineStep, Int) {
        try segment(type, label: "the \(S.name) step", in: words, from: start + 1, skipping: 0)
    }

    /// Parses `type` from `words[from...]`, ending at the first step name at which the words so far
    /// are valid options, and returns the value and the index where the next step starts.
    private static func segment<T: ParsableArguments>(
        _ type: T.Type, label: String, in words: [String], from start: Int, skipping: Int
    ) throws -> (T, Int) {
        var firstError: Error?
        var end = start
        while end <= words.count {
            if end == words.count || (end > start - 1 && PipelineSteps.names.contains(words[end]) && end >= start) {
                do {
                    return (try T.parse(Array(words[start..<end])), end)
                } catch {
                    if T.exitCode(for: error) == .success {   // --help
                        print(helpText(for: T.self, label: label))
                        throw ExitCode.success
                    }
                    if firstError == nil { firstError = error }
                }
            }
            end += 1
        }
        if let error = firstError { throw CommandFailure(message: "\(label): \(T.message(for: error))") }
        throw CommandFailure(message: "\(label) could not be read")
    }

    /// The options of one step, headed by the step's own name instead of the type it is parsed from.
    private static func helpText<T: ParsableArguments>(for type: T.Type, label: String) -> String {
        var lines = T.helpMessage().split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let first = lines.firstIndex(where: { $0.hasPrefix("USAGE:") }) {
            let options = lines[first].drop(while: { $0 != " " }).dropFirst().drop(while: { $0 != " " })
            let name = (type as? any PipelineStep.Type)?.name ?? "<input>"
            lines[first] = "USAGE: hokusai run ... \(name)\(options)"
        }
        return lines.joined(separator: "\n")
    }
}
