import Foundation
import Hokusai

// A fresh-process scenario runner for the process-level tests (#50, layer C).
//
// Runtime configuration freezes at first use, so each scenario needs its own
// process. The probe applies the configuration named on the command line, runs
// one scenario and prints `key=value` lines. It imports only the public module.
//
//   HokusaiProcessProbe <scenario> [key=value ...]
//
// Scenarios: status, sweep, overload, cancel, stream, streamAdmission, boundary, untrusted, stress.
// Keys: concurrent, queue, vips, block, evaluations, iterations, size.

let arguments = Array(CommandLine.arguments.dropFirst())
guard let scenario = arguments.first else {
    FileHandle.standardError.write(Data("usage: HokusaiProcessProbe <scenario> [key=value ...]\n".utf8))
    exit(64)
}
let options = Dictionary(
    uniqueKeysWithValues: arguments.dropFirst().compactMap { argument -> (String, String)? in
        guard let separator = argument.firstIndex(of: "=") else { return nil }
        return (String(argument[..<separator]), String(argument[argument.index(after: separator)...]))
    })

func integer(_ key: String) -> Int? { options[key].flatMap(Int.init) }

// MARK: - Input

/// What one evaluation does: enough work to hold a slot for a moment.
func evaluate(_ source: Data) async throws {
    _ = try await Hokusai(data: source).resize(width: 200).blur(sigma: 2).png().data()
}

// MARK: - Process facts

func peakResidentBytes() -> Int {
    var usage = rusage()
    #if os(macOS)
    guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
    return Int(usage.ru_maxrss)
    #else
    guard getrusage(RUSAGE_SELF.rawValue, &usage) == 0 else { return 0 }
    return Int(usage.ru_maxrss) * 1024
    #endif
}

actor Peaks {
    private(set) var active = 0
    private(set) var queued = 0
    func record(_ status: RuntimeStatus) {
        active = max(active, status.activeEvaluations)
        queued = max(queued, status.queuedEvaluations)
    }
}

/// Polls the scheduler counters until cancelled and keeps their maxima.
func sample(into peaks: Peaks) -> Task<Void, Never> {
    Task {
        while !Task.isCancelled {
            await peaks.record(Hokusai.runtimeStatus)
            try? await Task.sleep(nanoseconds: 300_000)
        }
    }
}

/// Waits for the scheduler counters to settle at zero, up to two seconds.
func settledStatus() async -> RuntimeStatus {
    var status = Hokusai.runtimeStatus
    for _ in 0..<200 where status.activeEvaluations != 0 || status.queuedEvaluations != 0 {
        try? await Task.sleep(nanoseconds: 10_000_000)
        status = Hokusai.runtimeStatus
    }
    return status
}

// MARK: - Configuration

func configuration() -> RuntimeConfiguration {
    RuntimeConfiguration(
        maxConcurrentEvaluations: integer("concurrent").map(ConcurrencyLimit.fixed) ?? .automatic,
        maxQueuedEvaluations: integer("queue"),
        vipsConcurrency: integer("vips").map(ConcurrencyLimit.fixed) ?? .automatic,
        blockUntrustedOperations: options["block"] == "1")
}

/// Applies the command-line configuration and reports how that went.
func applyConfiguration() -> String {
    do { try Hokusai.configure(configuration()); return "applied" } catch { return category(error) }
}

// MARK: - Scenarios

func runStatus() async {
    let before = Hokusai.runtimeStatus
    let configured = applyConfiguration()
    let configuredStatus = Hokusai.runtimeStatus

    if options["freeze"] == "1" { _ = try? Hokusai.capabilities() }
    let again = applyConfiguration()
    let frozen = Hokusai.runtimeStatus
    report([
        "frozenBeforeConfigure": before.isConfigurationFrozen,
        "configure": configured,
        "frozenAfterConfigure": configuredStatus.isConfigurationFrozen,
        "limit": configuredStatus.maxConcurrentEvaluations,
        "configureAgain": again,
        "frozenAtEnd": frozen.isConfigurationFrozen,
        "limitAtEnd": frozen.maxConcurrentEvaluations,
        "vipsConcurrency": frozen.vipsConcurrency.map(String.init) ?? "nil",
        "queueBound": frozen.configuration.maxQueuedEvaluations.map(String.init) ?? "nil",
    ])
    if options["initialize"] == "1" {
        try? Hokusai.initialize()
        report(["vipsConcurrencyAfterInitialize": Hokusai.runtimeStatus.vipsConcurrency.map(String.init) ?? "nil"])
    }
}

func runSweep() async {
    report(["configure": applyConfiguration()])
    let evaluations = integer("evaluations") ?? 24
    let source = tiff(width: integer("size") ?? 768, height: integer("size") ?? 768)
    let peaks = Peaks()
    let sampler = sample(into: peaks)

    var completed = 0, failed = 0
    await withTaskGroup(of: Bool.self) { group in
        for _ in 0..<evaluations { group.addTask { (try? await evaluate(source)) != nil } }
        for await succeeded in group { if succeeded { completed += 1 } else { failed += 1 } }
    }
    sampler.cancel()
    let final = await settledStatus()
    let maxActive = await peaks.active, maxQueued = await peaks.queued
    report([
        "limit": final.maxConcurrentEvaluations,
        "evaluations": evaluations,
        "completed": completed,
        "failed": failed,
        "maxActive": maxActive,
        "maxQueued": maxQueued,
        "finalActive": final.activeEvaluations,
        "finalQueued": final.queuedEvaluations,
    ])
}

func runOverload() async {
    report(["configure": applyConfiguration()])
    let evaluations = integer("evaluations") ?? 32
    let source = tiff(width: 768, height: 768)

    var counts: [String: Int] = [:]
    await withTaskGroup(of: String.self) { group in
        for _ in 0..<evaluations {
            group.addTask {
                do { try await evaluate(source); return "completed" } catch { return category(error) }
            }
        }
        for await outcome in group { counts[outcome, default: 0] += 1 }
    }
    let final = await settledStatus()
    report([
        "evaluations": evaluations,
        "completed": counts["completed", default: 0],
        "queueFull": counts["queueFull", default: 0],
        "otherFailures": evaluations - counts["completed", default: 0] - counts["queueFull", default: 0],
        "finalActive": final.activeEvaluations,
        "finalQueued": final.queuedEvaluations,
    ])
}

func runCancel() async {
    report(["configure": applyConfiguration()])
    let evaluations = integer("evaluations") ?? 24
    let source = tiff(width: 1024, height: 1024)

    let tasks = (0..<evaluations).map { _ in Task { try await evaluate(source) } }
    try? await Task.sleep(nanoseconds: 20_000_000)
    for (index, task) in tasks.enumerated() where index.isMultiple(of: 2) { task.cancel() }

    var counts: [String: Int] = [:]
    for task in tasks {
        do { try await task.value; counts["completed", default: 0] += 1 } catch { counts[category(error), default: 0] += 1 }
    }
    let final = await settledStatus()
    report([
        "evaluations": evaluations,
        "completed": counts["completed", default: 0],
        "cancelled": counts["cancelled", default: 0],
        "otherFailures": evaluations - counts["completed", default: 0] - counts["cancelled", default: 0],
        "finalActive": final.activeEvaluations,
        "finalQueued": final.queuedEvaluations,
    ])
}

struct ConsumerFailure: Error {}

/// Chunk streaming with one evaluation slot: a failing consumer and a
/// cancelled caller must both release it, or the last evaluation never runs.
func runStream() async {
    report(["configure": applyConfiguration()])
    let source = tiff(width: 1024, height: 1024)
    func pipeline() throws -> Hokusai { try Hokusai(data: source).png(compressionLevel: 0) }

    var streamed = 0, chunks = 0
    var plain = 0
    do {
        plain = try await pipeline().data().info.byteCount
        let info = try await pipeline().writeChunks(chunkSize: 32 * 1024) { streamed += $0.count; chunks += 1 }
        streamed = streamed == info.byteCount ? info.byteCount : -1
    } catch { report(["streamError": category(error)]) }

    var consumerOutcome = "completed"
    var seen = 0
    do {
        try await pipeline().writeChunks(chunkSize: 16 * 1024) { _ in
            seen += 1
            if seen == 2 { throw ConsumerFailure() }
        }
    } catch is ConsumerFailure { consumerOutcome = "consumerError" } catch { consumerOutcome = category(error) }

    let stalled = Task {
        try await pipeline().writeChunks(chunkSize: 16 * 1024) { _ in try await Task.sleep(nanoseconds: 60_000_000_000) }
    }
    try? await Task.sleep(nanoseconds: 300_000_000)
    let cancelStart = Date()
    stalled.cancel()
    var cancelOutcome = "completed"
    do { _ = try await stalled.value } catch { cancelOutcome = category(error) }
    let cancelSeconds = Date().timeIntervalSince(cancelStart)

    // With a single slot this only runs if both failures released it.
    var afterwards = "completed"
    do { try await evaluate(source) } catch { afterwards = category(error) }

    let final = await settledStatus()
    report([
        "plainBytes": plain,
        "streamedBytes": streamed,
        "chunks": chunks,
        "consumer": consumerOutcome,
        "consumerSaw": seen,
        "cancel": cancelOutcome,
        "cancelSeconds": String(format: "%.2f", cancelSeconds),
        "afterwards": afterwards,
        "finalActive": final.activeEvaluations,
        "finalQueued": final.queuedEvaluations,
    ])
}

final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

/// Chunk streaming when the scheduler rejects admission (#111): with one slot
/// held and the one queue place taken, another stream must fail promptly with
/// the typed queue error and never call its consumer.
func runStreamAdmission() async {
    report(["configure": applyConfiguration()])
    let source = tiff(width: 1024, height: 1024)
    func pipeline() throws -> Hokusai { try Hokusai(data: source).png(compressionLevel: 0) }

    let holder = Task {
        try await pipeline().writeChunks(chunkSize: 16 * 1024) { _ in try await Task.sleep(nanoseconds: 60_000_000_000) }
    }
    try? await Task.sleep(nanoseconds: 300_000_000)
    let waiter = Task { try await pipeline().writeChunks { _ in } }
    try? await Task.sleep(nanoseconds: 300_000_000)

    let calls = CallCounter()
    let started = Date()
    let outcome = await withTaskGroup(of: String.self) { group in
        group.addTask {
            do { _ = try await pipeline().writeChunks { _ in calls.increment() }; return "completed" } catch { return category(error) }
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            return "timeout"
        }
        let first = await group.next() ?? "none"
        group.cancelAll()
        return first
    }
    let seconds = Date().timeIntervalSince(started)

    holder.cancel()
    waiter.cancel()
    _ = try? await holder.value
    _ = try? await waiter.value
    var afterwards = "completed"
    do { try await evaluate(source) } catch { afterwards = category(error) }
    let final = await settledStatus()
    report([
        "outcome": outcome,
        "seconds": String(format: "%.2f", seconds),
        "consumerCalls": calls.count,
        "afterwards": afterwards,
        "finalActive": final.activeEvaluations,
        "finalQueued": final.queuedEvaluations,
    ])
}

func runUntrusted() async {
    report(["configure": applyConfiguration()])
    let svg = Data(#"<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"><rect width="8" height="8" fill="red"/></svg>"#.utf8)
    var svgOutcome = "decoded"
    do { _ = try await Hokusai(data: svg).png().data() } catch { svgOutcome = category(error) }
    var rasterOutcome = "decoded"
    do { try await evaluate(tiff(width: 64, height: 64)) } catch { rasterOutcome = category(error) }

    let capabilities = try? Hokusai.capabilities()
    report([
        "svg": svgOutcome,
        "raster": rasterOutcome,
        "blocked": (capabilities?.blockedInputFormats ?? []).map(\.rawValue).sorted().joined(separator: ","),
        "svgInput": capabilities?.canDecode(.svg) ?? false,
    ])
}

func runStress() async {
    report(["configure": applyConfiguration()])
    let iterations = integer("iterations") ?? 300
    let source = tiff(width: 512, height: 512)

    // Warm up so one-time allocations are not counted as growth.
    for _ in 0..<20 { try? await evaluate(source) }
    let baseline = peakResidentBytes()

    var failed = 0
    for _ in 0..<iterations / 10 {
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<10 { group.addTask { (try? await evaluate(source)) != nil } }
            for await succeeded in group where !succeeded { failed += 1 }
        }
    }
    let final = await settledStatus()
    report([
        "iterations": iterations / 10 * 10,
        "failed": failed,
        "baselineBytes": baseline,
        "peakBytes": peakResidentBytes(),
        "growthBytes": max(0, peakResidentBytes() - baseline),
        "finalActive": final.activeEvaluations,
        "finalQueued": final.queuedEvaluations,
    ])
}

switch scenario {
case "status": await runStatus()
case "sweep": await runSweep()
case "overload": await runOverload()
case "cancel": await runCancel()
case "stream": await runStream()
case "streamAdmission": await runStreamAdmission()
case "boundary": await runBoundary()
case "untrusted": await runUntrusted()
case "stress": await runStress()
default:
    FileHandle.standardError.write(Data("unknown scenario \(scenario)\n".utf8))
    exit(64)
}
