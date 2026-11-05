import Foundation
import Hokusai

/// The rows `inspect` shows for an image's source metadata.
///
/// Embedded blocks are only reported as present; their contents are never
/// dumped.
enum MetadataSummary {
    static func rows(for metadata: ImageMetadata) -> [(String, String)] {
        let oriented = metadata.orientedSize
        var rows: [(String, String)] = [
            ("Format", metadata.format?.rawValue ?? "unknown"),
            ("Width", "\(metadata.width) px"),
            ("Height", "\(metadata.height) px"),
        ]
        if let orientation = metadata.orientation {
            rows.append(("Orientation", "\(orientation) (\(oriented.width)×\(oriented.height) when displayed)"))
        }
        rows += [
            ("Channels", "\(metadata.pixel.channels)"),
            ("Has Alpha", metadata.pixel.hasAlpha ? "yes" : "no"),
            ("Pixels", "\(metadata.pixel.interpretation), \(metadata.pixel.sampleFormat)"
                + (metadata.pixel.bitsPerSample.map { ", \($0)-bit" } ?? "")),
        ]
        if let density = metadata.density {
            rows.append(("Density", String(format: "%.1f × %.1f dpi", density.horizontal, density.vertical)))
        }
        if metadata.pages.count > 1 {
            rows.append((metadata.isAnimated ? "Frames" : "Pages", "\(metadata.pages.count)"))
        }
        if let size = metadata.sourceByteSize {
            rows.append(("File size", "\(size) bytes"))
        }
        let embedded = [("EXIF", metadata.exif), ("ICC", metadata.iccProfile), ("XMP", metadata.xmp), ("IPTC", metadata.iptc)]
            .compactMap { $0.1 == nil ? nil : $0.0 }
        if !embedded.isEmpty {
            rows.append(("Embedded", embedded.joined(separator: ", ")))
        }
        return rows
    }

    /// The same facts as one JSON object, for scripts: the public `ImageMetadata`, without the
    /// contents of the embedded blocks.
    static func json(for metadata: ImageMetadata, input: String) throws -> String {
        let oriented = metadata.orientedSize
        var object: [String: Any] = [
            "input": input,
            "width": metadata.width,
            "height": metadata.height,
            "orientedWidth": oriented.width,
            "orientedHeight": oriented.height,
            "channels": metadata.pixel.channels,
            "hasAlpha": metadata.pixel.hasAlpha,
            "interpretation": "\(metadata.pixel.interpretation)",
            "sampleFormat": "\(metadata.pixel.sampleFormat)",
            "pages": metadata.pages.count,
            "isAnimated": metadata.isAnimated,
            "embedded": [
                "exif": metadata.exif != nil, "icc": metadata.iccProfile != nil, "xmp": metadata.xmp != nil, "iptc": metadata.iptc != nil,
            ],
        ]
        object["format"] = metadata.format?.rawValue ?? NSNull()
        if let orientation = metadata.orientation { object["orientation"] = "\(orientation)" }
        if let bits = metadata.pixel.bitsPerSample { object["bitsPerSample"] = bits }
        if let density = metadata.density { object["density"] = ["horizontal": density.horizontal, "vertical": density.vertical] }
        if let size = metadata.sourceByteSize { object["sourceByteSize"] = size }
        return String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }
}
