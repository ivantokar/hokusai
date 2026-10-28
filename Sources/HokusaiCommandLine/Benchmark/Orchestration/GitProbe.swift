import Foundation

/// The commit the measured code was built from, when it can be known.
enum GitProbe {
    static func head() -> String {
        if let override = ProcessInfo.processInfo.environment["HOKUSAI_GIT_COMMIT"], !override.isEmpty {
            return override
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "rev-parse", "HEAD"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return "unknown" }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return process.terminationStatus == 0 && !text.isEmpty ? text : "unknown"
    }
}
