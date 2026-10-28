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
}
