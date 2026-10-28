import ArgumentParser
import Foundation
import Hokusai
import Testing
@testable import HokusaiCommandLine

/// Failures are worded from the error's case and fields, never from native text.
@Suite struct ErrorPresentationTests {
    private func message(_ error: HokusaiError, verbose: Bool = false) -> String {
        ErrorTranslator.describe(error, verbose: verbose)
    }

    @Test func unsupportedNamesTheFeatureAndPointsToInfo() {
        let text = message(.unsupported(feature: "HEIF output", reason: "no encoder linked"))
        #expect(text.contains("HEIF output") && text.contains("no encoder linked") && text.contains("hokusai info"))
    }

    @Test func resourceFailuresShowTheConfiguredLimit() {
        let text = message(.resource(ResourceFailure(kind: .decodedPixels, limit: 100, actual: 256, reason: "too many pixels")))
        #expect(text.contains("decodedPixels") && text.contains("limit 100") && text.contains("actual 256"))
    }

    @Test func theNativeDiagnosticAppearsOnlyWhenVerbose() {
        let failure = HokusaiError.decode(FailureContext(operation: "load", reason: "bad data", diagnostic: "vips: unsupported"))
        #expect(!message(failure).contains("vips: unsupported"))
        #expect(message(failure, verbose: true).contains("vips: unsupported"))
        #expect(message(failure).contains("bad data"))
    }

    @Test func argumentParserErrorsAndCancellationKeepTheirMeaning() {
        #expect(ErrorTranslator.translate(ValidationError("x"), verbose: false) is ValidationError)
        #expect(ErrorTranslator.translate(ExitCode.failure, verbose: false) is ExitCode)
        #expect((ErrorTranslator.translate(CancellationError(), verbose: false) as? ExitCode)?.rawValue == 130)
    }

    @Test func otherErrorsBecomeASingleFailureLine() {
        let translated = ErrorTranslator.translate(HokusaiError.invalidInput(reason: "empty data"), verbose: false)
        #expect((translated as? CommandFailure)?.message.contains("empty data") == true)
    }
}

/// The CLI is a client of the public API: nothing in it may reach the native layer.
@Suite struct CommandLineBoundaryTests {
    private var sourcesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources")
    }

    private func sourceFiles(in target: String) throws -> [URL] {
        let enumerator = try #require(FileManager.default.enumerator(at: sourcesRoot.appendingPathComponent(target), includingPropertiesForKeys: nil))
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    @Test func noCommandImportsTheNativeOrInternalModules() throws {
        let forbidden = ["import CVips", "import CCairo", "@testable"]
        for target in ["HokusaiCommandLine", "HokusaiCLI"] {
            let files = try sourceFiles(in: target)
            #expect(!files.isEmpty, "\(target) has no sources")
            for file in files {
                let source = try String(contentsOf: file, encoding: .utf8)
                for word in forbidden {
                    #expect(!source.contains(word), "\(file.lastPathComponent) must not use \(word)")
                }
            }
        }
    }

    @Test func routineCommandsDoNotInitializeTheRuntimeThemselves() throws {
        for file in try sourceFiles(in: "HokusaiCommandLine") {
            let source = try String(contentsOf: file, encoding: .utf8)
            if file.lastPathComponent == "InfoCommand.swift" {
                #expect(source.contains("Hokusai.initialize()"), "info is the fail-fast diagnostic")
            } else {
                #expect(!source.contains("Hokusai.initialize()"), "\(file.lastPathComponent) relies on automatic initialization")
                #expect(!source.contains("shutdown"), "\(file.lastPathComponent) must not shut the runtime down")
            }
        }
    }
}
