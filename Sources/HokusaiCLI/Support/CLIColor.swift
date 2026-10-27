import Foundation
import Hokusai

extension CLIParser {
    /// Parses `r,g,b[,a]` (0...255) into a pipeline colour.
    static func parseColor(_ value: String) throws -> Color {
        let rgba = try parseRGBA(value)
        return Hokusai.rgba(red: rgba[0], green: rgba[1], blue: rgba[2], opacity: rgba[3])
    }
}
