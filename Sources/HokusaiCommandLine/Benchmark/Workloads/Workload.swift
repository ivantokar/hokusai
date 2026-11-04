import Foundation
import Hokusai

/// How a workload's output is received.
enum Delivery: Sendable, Equatable {
    /// The whole encoded output as `Data`.
    case buffer
    /// Chunks handed to a consumer as they are produced; a positive delay makes
    /// the consumer slow, which is what a slow client looks like to the encoder.
    case stream(consumerDelayMs: Int)

    var label: String {
        switch self {
        case .buffer: "buffer"
        case .stream(let delay): delay > 0 ? "stream, \(delay) ms per chunk" : "stream"
        }
    }
}

/// A named, repeatable piece of work built only from the public API.
protocol Workload: Sendable {
    var id: String { get }
    var summary: String { get }
    var delivery: Delivery { get }
    /// The terminal pipeline for one request reading `source`.
    func pipeline(reading source: URL) throws -> Hokusai
}

extension Workload {
    var delivery: Delivery { .buffer }
}

struct ClosureWorkload: Workload {
    let id: String
    let summary: String
    var delivery: Delivery = .buffer
    let build: @Sendable (Hokusai) throws -> Hokusai

    func pipeline(reading source: URL) throws -> Hokusai {
        try build(Hokusai(url: source))
    }
}

/// The small named suite `hokusai benchmark` can run.
enum WorkloadCatalog {
    static let all: [any Workload] = [
        ClosureWorkload(id: "thumbnail-jpeg", summary: "autoOrient, fit inside 400 px, JPEG") {
            try $0.autoOrient().resize(width: 400, fit: .inside).jpeg(quality: 80)
        },
        ClosureWorkload(id: "cover-webp", summary: "cover crop to 800x600, WebP") {
            try $0.resize(width: 800, height: 600, fit: .cover).webp(quality: 80)
        },
        ClosureWorkload(id: "blur-webp", summary: "Gaussian blur sigma 50, WebP") {
            try $0.blur(sigma: 50).webp(quality: 80)
        },
        ClosureWorkload(id: "resize-png", summary: "fit inside 1000 px, PNG") {
            try $0.resize(width: 1000, fit: .inside).png()
        },
        ClosureWorkload(
            id: "stream-ttfb", summary: "full-size uncompressed PNG streamed to a fast consumer; reports time to first byte",
            delivery: .stream(consumerDelayMs: 0)
        ) { try $0.png(compressionLevel: 0) },
        ClosureWorkload(
            id: "stream-slow-consumer",
            summary: "the same output to a consumer that takes 5 ms per 64 KiB chunk; peak memory should not follow output size",
            delivery: .stream(consumerDelayMs: 5)
        ) { try $0.png(compressionLevel: 0) },
        ClosureWorkload(id: "pdf-a4", summary: "fit inside A4 at 150 dpi, raster PDF") {
            try $0.resize(width: 1240, height: 1754, fit: .inside).pdf()
        },
    ]

    static let defaultIDs = ["thumbnail-jpeg", "cover-webp", "blur-webp"]

    static func workload(id: String) -> (any Workload)? {
        all.first { $0.id == id }
    }

    static var ids: [String] { all.map(\.id) }
}
