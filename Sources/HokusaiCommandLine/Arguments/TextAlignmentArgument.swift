import Hokusai

/// Text alignment words accepted by `--align`.
enum TextAlignmentArgument: String, CaseInsensitiveArgument {
    case left, center, right

    var alignment: TextAlignment {
        switch self {
        case .left: .left
        case .center: .center
        case .right: .right
        }
    }
}
