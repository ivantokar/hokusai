import ArgumentParser
import Foundation
import Testing
@testable import HokusaiCommandLine

/// `hokusai --version` (#147): the version the CLI reports is the version that was released.
@Suite struct VersionTests {
    @Test func versionMatchesNewestReleaseInChangelog() throws {
        // Tests/HokusaiTests/CommandLine/VersionTests.swift -> repository root.
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
        let heading = try #require(changelog.split(separator: "\n").first { line in
            line.hasPrefix("## [") && line.dropFirst(4).first?.isNumber == true
        })
        let released = heading.dropFirst(4).prefix { $0 != "]" }
        #expect(HokusaiVersion.current == String(released))
    }

    @Test func rootCommandReportsTheVersion() {
        #expect(HokusaiRootCommand.configuration.version == HokusaiVersion.current)
    }
}
