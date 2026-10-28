import ArgumentParser

/// Controls how much of a failure is shown.
struct DiagnosticsOptions: ParsableArguments {
    @Flag(name: .shortAndLong, help: "Show the native diagnostic of a failure, when there is one.")
    var verbose = false
}
