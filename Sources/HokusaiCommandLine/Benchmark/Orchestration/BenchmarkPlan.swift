/// The matrix a benchmark invocation covers: every workload under every
/// combination of the two independent concurrency dimensions.
struct BenchmarkPlan: Equatable {
    var workloads: [String]
    var input: String
    var profile: BenchmarkProfile
    var evaluations: [Int]
    var vipsConcurrency: [ConcurrencyChoice]
    /// Requests per batch; defaults to twice the evaluation limit so the queue is exercised.
    var requests: Int?

    /// One worker per cell, in a stable order.
    var cells: [WorkerSettings] {
        workloads.flatMap { workload in
            evaluations.flatMap { evaluation in
                vipsConcurrency.map { vips in
                    WorkerSettings(
                        workload: workload, input: input, profile: profile,
                        evaluations: evaluation, vipsConcurrency: vips,
                        requests: requests ?? max(2, evaluation * 2))
                }
            }
        }
    }
}
