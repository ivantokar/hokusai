import ArgumentParser
import Foundation
import Hokusai

/// Parses `r,g,b[,a]` colours written as 0...255 components.
///
/// Used as an option `transform`. Malformed, non-finite or out-of-range
/// components are rejected rather than clamped, so a typo cannot silently
/// turn into a different colour.
enum ColorParser {
    static func parse(_ value: String) throws -> Color {
        let parts = value.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 3 || parts.count == 4 else {
            throw ValidationError("expected 3 or 4 comma-separated components (r,g,b[,a]), got '\(value)'")
        }

        var components: [Double] = []
        for part in parts {
            guard let number = Double(part), number.isFinite else {
                throw ValidationError("'\(part)' is not a finite number")
            }
            guard (0...255).contains(number) else {
                throw ValidationError("component \(part) is outside 0...255")
            }
            components.append(number / 255)
        }

        let opacity = components.count == 4 ? components[3] : 1
        return Color(red: components[0], green: components[1], blue: components[2], opacity: opacity)
    }
}
