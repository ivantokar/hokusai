import ArgumentParser
import Hokusai

/// A concurrency setting on the command line: `auto` or a positive number.
enum ConcurrencyChoice: ExpressibleByArgument, Equatable, CustomStringConvertible {
    case automatic
    case fixed(Int)

    init?(argument: String) {
        if argument.lowercased() == "auto" {
            self = .automatic
        } else if let value = Int(argument), value >= 1 {
            self = .fixed(value)
        } else {
            return nil
        }
    }

    var limit: ConcurrencyLimit {
        switch self {
        case .automatic: .automatic
        case .fixed(let value): .fixed(value)
        }
    }

    var description: String {
        switch self {
        case .automatic: "auto"
        case .fixed(let value): "\(value)"
        }
    }

    /// Parses `1,2,4,auto` into choices; used as an option transform.
    static func parseList(_ value: String) throws -> [ConcurrencyChoice] {
        let choices = try value.split(separator: ",", omittingEmptySubsequences: false).map { word -> ConcurrencyChoice in
            guard let choice = ConcurrencyChoice(argument: String(word).trimmingCharactersInWhitespace) else {
                throw ValidationError("'\(word)' is not a positive number or 'auto'")
            }
            return choice
        }
        guard !choices.isEmpty else { throw ValidationError("expected a comma-separated list such as 1,2,4,auto") }
        return choices
    }
}

private extension String {
    var trimmingCharactersInWhitespace: String { trimmingCharacters(in: .whitespaces) }
}
