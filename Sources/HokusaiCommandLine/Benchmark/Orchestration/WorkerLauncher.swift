import Foundation

/// Starts a fresh process for one worker and returns what it printed.
///
/// The orchestrator depends on this protocol so it can be tested without
/// spawning processes.
protocol WorkerLauncher {
    func launch(arguments: [String]) async throws -> Data
}

struct WorkerFailure: Error, LocalizedError {
    let arguments: [String]
    let status: Int32
    let standardError: String

    var errorDescription: String? {
        let detail = standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        return "Benchmark worker (\(arguments.dropFirst(2).joined(separator: " "))) exited with status \(status)" + (detail.isEmpty ? "" : ": \(detail)")
    }
}

/// Re-executes this same binary, so a worker is always the code being measured.
struct ProcessWorkerLauncher: WorkerLauncher {
    let executable: URL

    init(executable: URL = Bundle.main.executableURL ?? URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])) {
        self.executable = executable
    }

    func launch(arguments: [String]) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global().async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                let output = Pipe()
                let errors = Pipe()
                process.standardOutput = output
                process.standardError = errors
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
                // Drain stderr concurrently so a chatty worker cannot fill the pipe and stall.
                let errorReader = DispatchQueue(label: "hokusai.bench.stderr")
                nonisolated(unsafe) var errorData = Data()
                let drained = DispatchSemaphore(value: 0)
                errorReader.async {
                    errorData = errors.fileHandleForReading.readDataToEndOfFile()
                    drained.signal()
                }
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                drained.wait()

                if process.terminationStatus == 0 {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: WorkerFailure(
                        arguments: arguments, status: process.terminationStatus,
                        standardError: String(decoding: errorData, as: UTF8.self)))
                }
            }
        }
    }
}
