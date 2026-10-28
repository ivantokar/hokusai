import Hokusai

/// The rows `info` shows for the linked runtime.
enum CapabilitySummary {
    static func rows(capabilities: RuntimeCapabilities, status: RuntimeStatus) -> [(String, String)] {
        [
            ("libvips", capabilities.libvipsVersion),
            ("Cairo", capabilities.cairoVersion),
            ("Input formats", list(capabilities.inputFormats)),
            ("Blocked input", list(capabilities.blockedInputFormats)),
            ("Output formats", list(capabilities.outputFormats)),
            ("Text rendering", capabilities.textRendering ? "yes" : "no"),
            ("Max evaluations", "\(status.maxConcurrentEvaluations)"),
            ("libvips threads", status.vipsConcurrency.map(String.init) ?? "unknown"),
        ]
    }

    private static func list(_ formats: Set<ImageFormat>) -> String {
        let names = ImageFormat.allCases.filter(formats.contains).map(\.rawValue)
        return names.isEmpty ? "none" : names.joined(separator: ", ")
    }
}
