import ArgumentParser
import Foundation
import Hokusai

/// A failure shaped for the terminal: one concise line, and a non-zero exit.
struct CommandFailure: Error, LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

/// Turns anything a command throws into what the operator should see.
///
/// ArgumentParser's own errors pass through untouched. Hokusai errors are
/// worded from their case and fields, never by matching native message text;
/// the native diagnostic is appended only when asked for.
enum ErrorTranslator {
    static func translate(_ error: Error, verbose: Bool) -> Error {
        switch error {
        case is ValidationError, is ExitCode, is CleanExit:
            return error
        case is CancellationError:
            return ExitCode(130)
        case let error as HokusaiError:
            return CommandFailure(message: describe(error, verbose: verbose))
        default:
            return CommandFailure(message: error.localizedDescription)
        }
    }

    static func describe(_ error: HokusaiError, verbose: Bool) -> String {
        switch error {
        case .unsupported(let feature, let reason):
            let detail = reason.map { ": \($0)" } ?? ""
            return "\(feature) is not supported by this build\(detail). Run `hokusai info` to see what is available."
        case .resource(let failure):
            let numbers = [failure.limit.map { "limit \($0)" }, failure.actual.map { "actual \($0)" }]
                .compactMap { $0 }.joined(separator: ", ")
            return "Limit reached (\(failure.kind)): \(failure.reason)" + (numbers.isEmpty ? "" : " (\(numbers))")
        case .decode(let context), .transform(let context), .encode(let context), .runtime(let context):
            let base = error.errorDescription ?? context.reason
            guard verbose, let diagnostic = context.diagnostic, !diagnostic.isEmpty else { return base }
            return "\(base)\nNative diagnostic: \(diagnostic)"
        case .invalidInput, .invalidOption, .io:
            return error.errorDescription ?? "\(error)"
        }
    }
}
