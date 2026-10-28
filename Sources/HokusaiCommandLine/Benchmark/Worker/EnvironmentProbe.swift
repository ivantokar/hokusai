import Foundation
import Hokusai

/// Facts about the machine and process, for the result's provenance.
enum EnvironmentProbe {
    static func current() throws -> BenchmarkEnvironment {
        let capabilities = try Hokusai.capabilities()
        return BenchmarkEnvironment(
            swiftVersion: swiftVersion,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            cpuCount: ProcessInfo.processInfo.activeProcessorCount,
            libvipsVersion: capabilities.libvipsVersion,
            cairoVersion: capabilities.cairoVersion,
            outputFormats: ImageFormat.allCases.filter(capabilities.outputFormats.contains).map(\.rawValue),
            textRendering: capabilities.textRendering)
    }

    /// The compiler this binary was built with, as far as the language exposes it.
    static var swiftVersion: String {
        #if compiler(>=6.4)
        "6.4 or newer"
        #elseif compiler(>=6.3)
        "6.3"
        #elseif compiler(>=6.2)
        "6.2"
        #elseif compiler(>=6.1)
        "6.1"
        #else
        "6.0"
        #endif
    }

    /// Peak resident set size of this process.
    static var peakResidentBytes: Int {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        #if os(macOS)
        return Int(usage.ru_maxrss)          // bytes
        #else
        return Int(usage.ru_maxrss) * 1024   // kilobytes
        #endif
    }
}
