import ArgumentParser
import Hokusai

/// `Gravity`, by compass word.
enum GravityArgument: String, CaseInsensitiveArgument {
    case center, north, south, east, west
    case northWest = "north-west", northEast = "north-east", southWest = "south-west", southEast = "south-east"
    var gravity: Gravity {
        switch self {
        case .center: .center
        case .north: .north
        case .south: .south
        case .east: .east
        case .west: .west
        case .northWest: .northWest
        case .northEast: .northEast
        case .southWest: .southWest
        case .southEast: .southEast
        }
    }
}

/// `ResizePosition`: a compass word, or a content-aware choice.
enum PositionArgument: String, CaseInsensitiveArgument {
    case center, north, south, east, west
    case northWest = "north-west", northEast = "north-east", southWest = "south-west", southEast = "south-east"
    case attention, entropy
    var position: ResizePosition {
        switch self {
        case .center: .center
        case .north: .north
        case .south: .south
        case .east: .east
        case .west: .west
        case .northWest: .northWest
        case .northEast: .northEast
        case .southWest: .southWest
        case .southEast: .southEast
        case .attention: .attention
        case .entropy: .entropy
        }
    }
}

enum InterpolationArgument: String, CaseInsensitiveArgument {
    case nearest, bilinear, bicubic, lbb, nohalo, vsqbs
    var interpolation: Interpolation { Interpolation(rawValue: rawValue) ?? .bilinear }
}

enum BlurPrecisionArgument: String, CaseInsensitiveArgument {
    case integer, float, approximate
    var precision: BlurPrecision { BlurPrecision(rawValue: rawValue) ?? .integer }
}

enum SmartCropStrategyArgument: String, CaseInsensitiveArgument {
    case attention, entropy
    var strategy: SmartCropStrategy { self == .attention ? .attention : .entropy }
}

/// How `extend` and `affine` fill the new edge: a background colour, or the image itself.
enum EdgeModeArgument: String, CaseInsensitiveArgument {
    case background, copy, `repeat`, mirror
    func mode(background: Color) -> ExtendMode {
        switch self {
        case .background: .background(background)
        case .copy: .copy
        case .repeat: .repeat
        case .mirror: .mirror
        }
    }
}

enum ColorSpaceArgument: String, CaseInsensitiveArgument {
    case srgb, grayscale
    var space: ColorSpace { self == .srgb ? .sRGB : .grayscale }
}

enum CompositingSpaceArgument: String, CaseInsensitiveArgument {
    case srgb, linear
    var space: CompositingSpace { self == .srgb ? .srgb : .linear }
}

/// `BlendMode`, by its case name in kebab-case (`destination-over`, `soft-light`).
struct BlendArgument: ExpressibleByArgument {
    let mode: BlendMode

    init?(argument: String) {
        guard let found = BlendMode.allCases.first(where: { Self.word($0) == argument.lowercased() }) else { return nil }
        mode = found
    }

    init(_ mode: BlendMode) { self.mode = mode }

    static var allValueStrings: [String] { BlendMode.allCases.map(word) }
    var defaultValueDescription: String { Self.word(mode) }

    private static func word(_ mode: BlendMode) -> String {
        var result = ""
        for character in String(describing: mode) {
            if character.isUppercase { result += "-" + character.lowercased() } else { result.append(character) }
        }
        return result
    }
}

/// `--x`/`--y` or `--gravity` with offsets: where an overlay or a drawn text sits (`Placement`).
struct PlacementOptions: ParsableArguments {
    @Option(help: "Left edge, in pixels (`Placement.at`).")
    var x: Int?

    @Option(help: "Top edge, in pixels (`Placement.at`).")
    var y: Int?

    @Option(help: "Place by compass word instead of x and y (`Placement.gravity`).")
    var gravity: GravityArgument?

    @Option(help: "Horizontal offset from the gravity position.")
    var offsetX = 0

    @Option(help: "Vertical offset from the gravity position.")
    var offsetY = 0

    @Flag(help: "Tile the overlay over the whole image from the gravity position (`Placement.tile`).")
    var tile = false

    func validate() throws {
        if gravity != nil, x != nil || y != nil { throw ValidationError("use --x and --y, or --gravity, not both") }
        if gravity == nil, !tile, offsetX != 0 || offsetY != 0 { throw ValidationError("--offset-x and --offset-y need --gravity") }
        if tile, x != nil || y != nil || offsetX != 0 || offsetY != 0 { throw ValidationError("--tile takes --gravity only") }
    }

    var placement: Placement {
        if tile { return .tile(gravity: gravity?.gravity ?? .northWest) }
        if let gravity { return .gravity(gravity.gravity, offsetX: offsetX, offsetY: offsetY) }
        return .at(x: x ?? 0, y: y ?? 0)
    }
}
