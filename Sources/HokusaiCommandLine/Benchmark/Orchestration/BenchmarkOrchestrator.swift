import Foundation

/// Runs a plan by launching one fresh worker process per cell and collecting
/// the results. Each worker owns one frozen runtime configuration, so no cell
/// can contaminate the next through cache or runtime state.
struct BenchmarkOrchestrator {
    let launcher: any WorkerLauncher
    var onCellStart: (WorkerSettings) -> Void = { _ in }

    func run(_ plan: BenchmarkPlan, gitCommit: String, hokusaiVersion: String) async throws -> BenchmarkRun {
        var cells: [CellMeasurement] = []
        for settings in plan.cells {
            onCellStart(settings)
            let output = try await launcher.launch(arguments: settings.arguments)
            cells.append(try Self.decode(output))
        }
        return BenchmarkRun(
            schemaVersion: BenchmarkSchema.version,
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            gitCommit: gitCommit,
            hokusaiVersion: hokusaiVersion,
            profile: plan.profile.rawValue,
            cells: cells)
    }

    static func decode(_ output: Data) throws -> CellMeasurement {
        do {
            let cell = try JSONDecoder().decode(CellMeasurement.self, from: output)
            guard cell.schemaVersion == BenchmarkSchema.version else {
                throw BenchmarkError("worker reported result schema \(cell.schemaVersion), expected \(BenchmarkSchema.version)")
            }
            return cell
        } catch let error as BenchmarkError {
            throw error
        } catch {
            throw BenchmarkError("worker output is not a benchmark result: \(error.localizedDescription)")
        }
    }
}

struct BenchmarkError: Error, LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
