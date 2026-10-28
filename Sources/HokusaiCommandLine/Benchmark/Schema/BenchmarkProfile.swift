import ArgumentParser

/// How much to measure. Quick is for local smoke and comparison; stable has
/// enough samples for tail latency.
enum BenchmarkProfile: String, CaseIterable, ExpressibleByArgument, Codable {
    case quick
    case stable

    var warmupIterations: Int {
        switch self {
        case .quick: 1
        case .stable: 3
        }
    }

    var measuredIterations: Int {
        switch self {
        case .quick: 5
        case .stable: 50
        }
    }
}
