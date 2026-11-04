import Foundation
import Hokusai
import Testing

/// Floating-point extremes beyond the one-argument boundary sweep (#121): matrix
/// entries together, subnormals in a rotation and NaN in colour components. Each
/// call must succeed or fail with a typed `HokusaiError`; a trap ends the process.
@Suite struct FloatingPointExtremesTests {
    private static let extremes: [Double] = [
        0, -0.0, 1, -1, 0.5, 1e-300, 5e-324, -5e-324, 1e300, -1e300, .greatestFiniteMagnitude, .leastNormalMagnitude,
        .infinity, -.infinity, .nan,
    ]

    private func small() throws -> Hokusai {
        try Raster(width: 12, height: 9) { x, y in [UInt8(x * 20), UInt8(y * 25), 120, 255] }.pipeline()
    }

    /// Runs the pipeline to bytes; returns a description when it breaks the contract.
    private func contract(_ build: () throws -> Hokusai) async -> String? {
        do {
            _ = try await build().png().data()
            return nil
        } catch is HokusaiError {
            return nil
        } catch {
            return "\(error)"
        }
    }

    @Test(.timeLimit(.minutes(3)))
    func affineMatrixEntriesTogetherNeverTrap() async throws {
        let image = try small()
        let area = AffineArea(x: 0, y: 0, width: 8, height: 8)
        var failures: [String] = []
        var count = 0
        // Every pair of entries takes every pair of extreme values; the others stay identity.
        for (first, second) in [(0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3)] {
            for p in Self.extremes {
                for q in Self.extremes {
                    var entries = [1.0, 0, 0, 1]
                    entries[first] = p
                    entries[second] = q
                    let matrix = AffineMatrix(a: entries[0], b: entries[1], c: entries[2], d: entries[3])
                    count += 1
                    if let failure = await contract({ try image.affine(matrix, outputArea: area) }) {
                        failures.append("\(entries): \(failure)")
                    }
                }
            }
        }
        #expect(count > 1000)
        #expect(failures.isEmpty, "\(failures.prefix(5))")
    }

    @Test(.timeLimit(.minutes(3)))
    func rotationByExtremeAnglesNeverTraps() async throws {
        let image = try small()
        var failures: [String] = []
        for degrees in Self.extremes + [90 + 5e-324, 89.99999999999999, 1e-9, 360 * 1e15] {
            for interpolation in [Interpolation.nearest, .bilinear, .bicubic] {
                if let failure = await contract({ try image.rotate(by: degrees, background: .white, interpolation: interpolation) }) {
                    failures.append("\(degrees) \(interpolation): \(failure)")
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.prefix(5))")
    }

    @Test(.timeLimit(.minutes(3)))
    func colourComponentsOfNaNAndInfinityNeverTrap() async throws {
        let image = try small()
        var failures: [String] = []
        for p in Self.extremes {
            for q in [0.5, Double.nan, .infinity] {
                let colour = Color(red: p, green: q, blue: p, opacity: q)
                let cases: [(String, () throws -> Hokusai)] = [
                    ("extend", { try image.extend(top: 2, left: 2, bottom: 2, right: 2, mode: .background(colour)) }),
                    ("rotate", { try image.rotate(by: 33, background: colour) }),
                    ("contain", { try image.resize(width: 20, height: 20, fit: .contain, background: colour) }),
                    ("flatten", { try image.flatten(background: colour) }),
                    ("tint", { try image.tint(colour) }),
                ]
                for (name, build) in cases {
                    if let failure = await contract(build) { failures.append("\(name) \(p) \(q): \(failure)") }
                }
            }
        }
        #expect(failures.isEmpty, "\(failures.prefix(5))")
    }
}
