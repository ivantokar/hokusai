import ArgumentParser

/// A closed set of command-line words, matched without regard to case.
///
/// Anything outside the set is rejected by ArgumentParser, which lists the
/// accepted words; an unknown value never falls back to a default.
protocol CaseInsensitiveArgument: ExpressibleByArgument, CaseIterable, RawRepresentable where RawValue == String {}

extension CaseInsensitiveArgument {
    init?(argument: String) {
        self.init(rawValue: argument.lowercased())
    }
}
