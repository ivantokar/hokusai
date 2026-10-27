import Foundation
import Hokusai

extension CLIParser {
    /// Parses `r,g,b[,a]` (0...255) into a pipeline colour.
    static func parseColor(_ value: String) throws -> Color {
        let rgba = try parseRGBA(value)
        return Color(red: rgba[0] / 255, green: rgba[1] / 255, blue: rgba[2] / 255, opacity: rgba[3] / 255)
    }
}
