import Foundation
import Hokusai
import Testing

/// Damaged files for every decoder (#121): truncated, bit-flipped, header-scribbled
/// and padded. The contract is that decoding either succeeds or fails with a typed
/// `HokusaiError`, in bounded time. A trap would end the test process, and a hang
/// is caught by the per-file deadline.
@Suite struct MalformedInputTests {
    /// A small, seeded generator so a failure can be reproduced from its name.
    private struct Generator: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return state
        }
    }

    private func mutants(of data: Data, seed: UInt64, count: Int) -> [(name: String, data: Data)] {
        var generator = Generator(state: seed &* 0x9E37_79B9_7F4A_7C15 | 1)
        var result: [(String, Data)] = []
        let bytes = [UInt8](data)
        guard bytes.count > 16 else { return [] }
        for index in 0..<count {
            var mutated = bytes
            let kind = index % 5
            switch kind {
            case 0:   // truncated at a random point
                mutated = Array(mutated.prefix(Int.random(in: 1..<mutated.count, using: &generator)))
            case 1:   // a few flipped bits anywhere
                for _ in 0..<Int.random(in: 1...8, using: &generator) {
                    mutated[Int.random(in: 0..<mutated.count, using: &generator)] ^= UInt8(1 << Int.random(in: 0..<8, using: &generator))
                }
            case 2:   // the header scribbled over, where sizes and offsets live
                let span = min(48, mutated.count)
                for _ in 0..<Int.random(in: 1...6, using: &generator) {
                    mutated[Int.random(in: 0..<span, using: &generator)] = UInt8.random(in: 0...255, using: &generator)
                }
            case 3:   // header fields set to extremes
                let span = min(40, mutated.count)
                for _ in 0..<Int.random(in: 1...4, using: &generator) {
                    mutated[Int.random(in: 4..<span, using: &generator)] = [0x00, 0xFF, 0x7F, 0x80].randomElement(using: &generator)!
                }
            default:  // trailing garbage and a cut in the middle
                mutated += (0..<Int.random(in: 1...64, using: &generator)).map { _ in UInt8.random(in: 0...255, using: &generator) }
                let cut = Int.random(in: 1..<mutated.count, using: &generator)
                mutated.removeSubrange(cut..<min(mutated.count, cut + Int.random(in: 1...32, using: &generator)))
            }
            result.append(("seed \(seed) mutant \(index) kind \(kind)", Data(mutated)))
        }
        return result
    }

    /// Decodes, transforms and encodes; returns a description of any failure of the contract.
    private func attempt(_ data: Data, options: InputOptions, label: String) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask {
                do {
                    _ = try await Hokusai(data: data, options: options).resize(width: 16).png().data()
                    return nil
                } catch is HokusaiError {
                    return nil
                } catch {
                    return "\(label): an untyped error \(error)"
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(20))
                return "\(label): did not finish in 20 s"
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func sources() async throws -> [(name: String, data: Data)] {
        var sources: [(String, Data)] = try ["landscape-asym.jpg", "cmyk.jpg", "rgb16.png", "palette.png", "rgba-alpha.png", "animated.gif", "animated.webp", "multipage.tif"]
            .map { file in
                let parts = file.split(separator: ".")
                return (file, try fixtureData(named: String(parts[0]), ext: String(parts[1])))
            }
        // Formats the fixtures do not cover are produced by the encoders, when this build has them.
        let capabilities = try Hokusai.capabilities()
        let base = try Hokusai(data: fixtureData(named: "landscape-asym", ext: "jpg")).resize(width: 64)
        if capabilities.outputFormats.contains(.avif) { sources.append(("avif", try await base.avif().data().data)) }
        if capabilities.outputFormats.contains(.heif) { sources.append(("heif", try await base.heif().data().data)) }
        // Each of these needs its encoder in this libvips build (the baseline job has no GIF encoder).
        if capabilities.outputFormats.contains(.tiff) { sources.append(("tiff", try await base.tiff().data().data)) }
        if capabilities.outputFormats.contains(.webp) { sources.append(("webp", try await base.webp().data().data)) }
        if capabilities.outputFormats.contains(.gif) { sources.append(("gif", try await base.gif().data().data)) }
        if capabilities.inputFormats.contains(.svg) {
            sources.append(("svg", Data("<svg xmlns='http://www.w3.org/2000/svg' width='40' height='30'><rect width='40' height='30' fill='red'/></svg>".utf8)))
        }
        return sources
    }

    @Test(.timeLimit(.minutes(10)))
    func damagedFilesFailWithTypedErrorsAndNeverTrapOrHang() async throws {
        var failures: [String] = []
        var attempts = 0
        let levels: [(String, InputOptions.DecodeFailureLevel)] = [("none", .none), ("truncated", .truncated), ("error", .error), ("warning", .warning)]
        for (name, data) in try await sources() {
            for (levelName, level) in levels {
                var options = InputOptions()
                options.failOn = level
                // `.none` decodes whatever a damaged file claims, padding the missing data, so a
                // 300 byte PNG that claims 130 million pixels costs a gigabyte and tens of seconds
                // within the default limit. That is the documented meaning of `.none`; the test
                // judges hangs, so it bounds the claim as a service using `.none` should.
                if level == .none { options.limits = InputLimits(maxPixels: 4_000_000) }
                for mutant in mutants(of: data, seed: name.utf8.reduce(UInt64(7)) { $0 &* 31 &+ UInt64($1) }, count: Int(ProcessInfo.processInfo.environment["HOKUSAI_FUZZ_MUTANTS"] ?? "") ?? 20) {
                    attempts += 1
                    if let failure = await attempt(mutant.data, options: options, label: "\(name) failOn \(levelName), \(mutant.name)") {
                        failures.append(failure)
                        // HOKUSAI_FUZZ_DUMP=<directory> keeps the offending files for a closer look.
                        if let directory = ProcessInfo.processInfo.environment["HOKUSAI_FUZZ_DUMP"] {
                            let file = URL(fileURLWithPath: directory).appendingPathComponent("\(name)-\(levelName)-\(attempts).bin")
                            try? mutant.data.write(to: file)
                        }
                    }
                }
            }
        }
        #expect(attempts > 400)
        #expect(failures.isEmpty, "\(failures.prefix(10).joined(separator: "\n"))")
    }

    @Test func aTinyPixelLimitIsAResourceErrorForEveryFormat() async throws {
        for (name, data) in try await sources() {
            var options = InputOptions()
            options.limits = InputLimits(maxPixels: 1)
            do {
                _ = try await Hokusai(data: data, options: options).png().data()
                Issue.record("\(name): a 1 pixel limit did not stop the decode")
            } catch HokusaiError.resource {
            } catch {
                Issue.record("\(name): expected a resource error, got \(error)")
            }
        }
    }
}
