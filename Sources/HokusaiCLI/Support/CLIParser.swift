import Foundation
import ArgumentParser
import Hokusai
import Prompt

enum CLIParser {
    static func parseFit(_ value: String) -> ResizeFit {
        switch value.lowercased() {
        case "inside": return .inside
        case "outside": return .outside
        case "fill": return .fill
        case "cover": return .cover
        case "contain": return .contain
        default: return .inside
        }
    }

    static func parseKernel(_ value: String) -> Kernel {
        switch value.lowercased() {
        case "nearest": return .nearest
        case "linear": return .linear
        case "cubic": return .cubic
        case "mitchell": return .mitchell
        case "lanczos2": return .lanczos2
        default: return .lanczos3
        }
    }

    static func parsePipelineKernel(_ value: String) -> ResizeKernel {
        switch parseKernel(value) {
        case .nearest: .nearest
        case .linear: .linear
        case .cubic: .cubic
        case .mitchell: .mitchell
        case .lanczos2: .lanczos2
        case .lanczos3: .lanczos3
        }
    }

    static func configurePipelineOutput(
        _ pipeline: Hokusai,
        format: ImageFormat,
        quality: Int?,
        compression: Int?,
        progressive: Bool,
        stripMetadata: Bool,
        lossless: Bool,
        effort: Int?
    ) throws -> Hokusai {
        let configured: Hokusai
        switch format {
        case .jpeg:
            configured = try pipeline.jpeg(quality: quality ?? 80, progressive: progressive)
        case .png:
            configured = try pipeline.png(compressionLevel: compression ?? 6, progressive: progressive)
        case .webp:
            configured = try pipeline.webp(quality: quality ?? 80, effort: effort ?? 4, lossless: lossless)
        case .avif:
            configured = try pipeline.avif(quality: quality ?? 50, effort: effort ?? 4, lossless: lossless)
        case .pdf:
            configured = try pipeline.pdf()
        case .gif, .tiff, .heif, .svg:
            throw ValidationError("The 1.0 pipeline CLI does not support output format: \(format.rawValue)")
        }
        return try stripMetadata ? configured.removeMetadata() : configured.preserveMetadata()
    }

    static func parseTextAlign(_ value: String) -> TextAlignment {
        switch value.lowercased() {
        case "center": return .center
        case "right": return .right
        default: return .left
        }
    }

    static func parseFormat(_ value: String?, fallbackPath: String?) throws -> ImageFormat {
        if let value, !value.isEmpty {
            if let format = parseFormatAlias(value) {
                return format
            }
            throw ValidationError("Unsupported format: \(value)")
        }

        if let fallbackPath,
           let ext = fallbackPath.split(separator: ".").last,
           let format = parseFormatAlias(String(ext)) {
            return format
        }

        throw ValidationError("Could not infer image format. Use --format or output extension.")
    }

    private static func parseFormatAlias(_ value: String) -> ImageFormat? {
        let normalized = value.lowercased()
        if normalized == "jpg" { return .jpeg }
        if normalized == "tif" { return .tiff }
        if normalized == "heic" { return .heif }
        return ImageFormat(rawValue: normalized)
    }

    static func parseThumbnailPosition(_ value: String) throws -> ResizePosition? {
        switch value.lowercased() {
        case "none": return nil
        case "centre", "center": return .center
        case "attention": return .attention
        case "entropy": return .entropy
        default:
            throw ValidationError("Invalid crop strategy '\(value)'. Valid values: none, centre (or center), attention, entropy.")
        }
    }

    static func validateDimension(_ value: Int, name: String) throws {
        guard value > 0 else {
            throw ValidationError("--\(name) must be greater than zero.")
        }
        guard Int32(exactly: value) != nil else {
            throw ValidationError("--\(name) must be at most \(Int32.max).")
        }
    }

    static func parseRGBA(_ value: String) throws -> [Double] {
        let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 3 || parts.count == 4 else {
            throw ValidationError("RGBA must have 3 or 4 comma-separated numbers")
        }

        var numbers: [Double] = []
        for part in parts {
            guard let number = Double(part) else {
                throw ValidationError("Invalid color component: \(part)")
            }
            numbers.append(min(max(number, 0), 255))
        }

        if numbers.count == 3 {
            numbers.append(255)
        }

        return numbers
    }

}
