import Foundation
import Testing

/// Behaviour that depends on process-global state: configuration that freezes
/// at first use, the scheduler under load, blocked loaders and memory. Each
/// test runs its scenario in a fresh process.
@Suite struct RuntimeProcessTests {
    // MARK: - Configuration

    @Test func configurationIsAppliedOnceBeforeFirstUse() async throws {
        let result = try await runProbe("status", ["concurrent": "3", "queue": "7", "vips": "2", "initialize": "1"])
        #expect(result.status == 0, "\(result.errorOutput)")
        #expect(result.flag("frozenBeforeConfigure") == false)
        #expect(result.values["configure"] == "applied")
        #expect(result.flag("frozenAfterConfigure") == false, "configuring must not freeze by itself")
        #expect(result.integer("limit") == 3)
        #expect(result.values["configureAgain"] == "runtime", "a second configure must be refused")
        #expect(result.integer("limitAtEnd") == 3)
        #expect(result.values["queueBound"] == "7")
        #expect(result.values["vipsConcurrencyAfterInitialize"] == "2")
    }

    @Test func configurationFreezesAtTheFirstRuntimeUse() async throws {
        let result = try await runProbe("status", ["concurrent": "5", "freeze": "1"])
        #expect(result.values["configure"] == "applied")
        // Using the runtime between the two calls froze the first configuration.
        #expect(result.flag("frozenAtEnd") == true)
        #expect(result.values["configureAgain"] == "runtime")
        #expect(result.integer("limitAtEnd") == 5)
    }

    @Test func aProcessThatNeverConfiguresUsesDefaults() async throws {
        let result = try await runProbe("status", [:])
        #expect(result.values["configure"] == "applied")
        #expect(result.integer("limit").map { $0 >= 1 } == true)
        #expect(result.values["queueBound"] == "nil")
    }

    @Test func invalidConfigurationIsRejectedAndDoesNotFreeze() async throws {
        let result = try await runProbe("status", ["concurrent": "0"])
        #expect(result.values["configure"] == "invalidOption")
        #expect(result.flag("frozenAfterConfigure") == false)
    }

    // MARK: - Scheduler capacity

    @Test(arguments: [1, 2, 4])
    func activeEvaluationsNeverExceedTheConfiguredCapacity(capacity: Int) async throws {
        let result = try await runProbe("sweep", ["concurrent": "\(capacity)", "evaluations": "24"])
        #expect(result.status == 0, "\(result.errorOutput)")
        #expect(result.integer("limit") == capacity)
        #expect(result.integer("completed") == 24 && result.integer("failed") == 0)
        let maxActive = try #require(result.integer("maxActive"))
        #expect(maxActive >= 1 && maxActive <= capacity, "observed \(maxActive) active with capacity \(capacity)")
        #expect(result.integer("finalActive") == 0 && result.integer("finalQueued") == 0)
    }

    @Test func aBoundedQueueRejectsOverloadWithATypedError() async throws {
        let result = try await runProbe("overload", ["concurrent": "1", "queue": "2", "evaluations": "32"])
        #expect(result.status == 0, "\(result.errorOutput)")
        let completed = try #require(result.integer("completed"))
        let rejected = try #require(result.integer("queueFull"))
        #expect(result.integer("otherFailures") == 0)
        #expect(completed + rejected == 32)
        #expect(completed >= 1)
        #expect(rejected >= 1, "32 simultaneous evaluations cannot all fit one slot and a queue of two")
        #expect(result.integer("finalActive") == 0 && result.integer("finalQueued") == 0)
    }

    @Test func anUnboundedQueueAcceptsEverything() async throws {
        let result = try await runProbe("overload", ["concurrent": "1", "evaluations": "16"])
        #expect(result.integer("completed") == 16)
        #expect(result.integer("queueFull") == 0)
    }

    /// With one slot, a consumer that throws and a caller that cancels while the
    /// encoder is blocked must each give the slot back.
    @Test func chunkStreamingReleasesTheSlotOnConsumerErrorAndCancellation() async throws {
        let result = try await runProbe("stream", ["concurrent": "1"])
        #expect(result.integer("streamedBytes") == result.integer("plainBytes"))
        #expect((result.integer("chunks") ?? 0) > 1)
        #expect(result.values["consumer"] == "consumerError")
        #expect(result.integer("consumerSaw") == 2)
        #expect(result.values["cancel"] == "cancelled")
        #expect((result.values["cancelSeconds"].flatMap(Double.init) ?? 99) < 10)
        #expect(result.values["afterwards"] == "completed")
        #expect(result.integer("finalActive") == 0 && result.integer("finalQueued") == 0)
    }

    @Test func cancellationReleasesCapacityAndLeavesNoCountersBehind() async throws {
        let result = try await runProbe("cancel", ["concurrent": "1", "evaluations": "24"])
        #expect(result.status == 0, "\(result.errorOutput)")
        #expect(result.integer("otherFailures") == 0)
        #expect((result.integer("completed") ?? 0) + (result.integer("cancelled") ?? 0) == 24)
        #expect(result.integer("finalActive") == 0 && result.integer("finalQueued") == 0)
    }

    // MARK: - Untrusted loaders

    @Test func blockedLoadersFailAsDecodeWhileRasterFormatsKeepWorking() async throws {
        let result = try await runProbe("untrusted", ["block": "1"])
        #expect(result.status == 0, "\(result.errorOutput)")
        #expect(result.values["svg"] == "decode")
        #expect(result.values["raster"] == "decoded")
        #expect(result.flag("svgInput") == false)
        #expect(result.values["blocked"]?.contains("svg") == true)
    }

    @Test func untrustedLoadersAreAvailableUnlessBlocked() async throws {
        let result = try await runProbe("untrusted", [:])
        #expect(result.values["raster"] == "decoded")
        #expect(result.values["blocked"] == "")
        // SVG is optional; when this build can read it, it must succeed.
        if result.flag("svgInput") == true { #expect(result.values["svg"] == "decoded") }
    }

    @Test func theEnvironmentSwitchBlocksLoadersWithoutAnyConfiguration() async throws {
        let result = try await runProbe("untrusted", [:], environment: ["VIPS_BLOCK_UNTRUSTED": "1"])
        #expect(result.values["raster"] == "decoded")
        #expect(result.values["svg"] != "decoded")
    }

    // MARK: - Memory

    /// A leak guard, not a benchmark: repeated evaluations must not grow the
    /// process without bound. `HOKUSAI_STRESS_ITERATIONS` lengthens the run for
    /// the scheduled job.
    @Test func repeatedEvaluationsDoNotGrowResidentMemoryWithoutBound() async throws {
        let iterations = ProcessInfo.processInfo.environment["HOKUSAI_STRESS_ITERATIONS"].flatMap(Int.init) ?? 300
        let result = try await runProbe("stress", ["concurrent": "4", "iterations": "\(iterations)"])
        #expect(result.status == 0, "\(result.errorOutput)")
        #expect(result.integer("failed") == 0)
        #expect(result.integer("finalActive") == 0 && result.integer("finalQueued") == 0)
        // Sanitizers inflate resident memory, so only a plain run is bounded.
        guard ProcessInfo.processInfo.environment["HOKUSAI_SANITIZED"] == nil else { return }
        let growth = try #require(result.integer("growthBytes"))
        #expect(growth < 256 * 1024 * 1024, "resident memory grew by \(growth / 1_048_576) MiB over \(iterations) evaluations")
    }
}
