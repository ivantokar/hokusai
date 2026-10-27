import Foundation

/// The semantics-preserving planning rules Hokusai may apply (#39).
///
/// The contract is that a pipeline means exactly its written operations in
/// their written order. The planner may change *how* that executes, never
/// *what* it produces, so it only ever applies the whitelisted rules below.
///
/// Deliberately **not** done (each needs its own benchmark-backed proposal):
/// reordering operations, fusing consecutive resizes or geometry, moving
/// analytical operations such as `trim` or smart crop, automatic gamma around
/// resize, automatic `copy_memory`/tile caches, a process-wide result cache,
/// choosing `.sequential` access, or deduplicating structurally equal plans
/// from independent `Hokusai` values. libvips already provides demand-driven
/// evaluation and its own operation cache; Hokusai adds none.
enum PlannerRule: String, CaseIterable, Sendable {
    /// A rotation by a whole number of turns is the identity.
    case identityRotation

    /// Compositing an empty layer list is the identity.
    case emptyComposite

    /// Within one evaluation, a node shared by several consumers (for example
    /// a logo used as two layers, or a layer derived from the base image) is
    /// built once. Scope is a single terminal evaluation; nothing outlives it,
    /// and sources opened for `.sequential` access are never shared because
    /// one forward-only stream cannot serve two readers.
    case subplanMemoisation

    /// A JPEG source whose first operation is `resize` (optionally after
    /// `autoOrient`) is decoded at a reduced size when the result still has
    /// at least the pixels the resize needs. The target size is computed from
    /// the full-resolution header, so dimensions are exactly those of a normal
    /// decode and resize; only pixel values may differ, within codec
    /// tolerance. Any other operation before the resize, any other codec, an
    /// explicit page, or a source node already built for another consumer in
    /// the same evaluation disables it.
    case shrinkOnLoad
}

/// Test and benchmark control over the planner. Production code uses
/// ``default``; there is no public API for it.
struct PlannerOptions: Sendable, Equatable {
    var disabled: Set<PlannerRule> = []

    static let `default` = PlannerOptions()

    func isEnabled(_ rule: PlannerRule) -> Bool { !disabled.contains(rule) }

    /// The reference lowering: every optimisation off.
    static let reference = PlannerOptions(disabled: Set(PlannerRule.allCases))
}

/// One written operation and, when the planner proved it an identity, the
/// rule that lets lowering skip it. The plan is always one-to-one with the
/// written operations, in order.
struct PlannedStep {
    let operation: ImageOperation
    let skippedBy: PlannerRule?
}

enum Planner {
    /// Marks provable identity operations. Never reorders, merges, or drops
    /// entries, so position in the result equals position in the pipeline.
    static func plan(_ operations: [ImageOperation], options: PlannerOptions) -> [PlannedStep] {
        operations.map { PlannedStep(operation: $0, skippedBy: identityRule(for: $0, options: options)) }
    }

    private static func identityRule(for operation: ImageOperation, options: PlannerOptions) -> PlannerRule? {
        switch operation {
        case .rotate(let degrees, _, _)
            where options.isEnabled(.identityRotation) && degrees.truncatingRemainder(dividingBy: 360) == 0:
            // Exact whole turns only. A resize to unchanged dimensions, a colour
            // conversion that looks equivalent, or a zero-looking blend are not
            // identities: they carry resampling, interpretation, and blend contracts.
            return .identityRotation
        case .composite(let layers) where options.isEnabled(.emptyComposite) && layers.isEmpty:
            return .emptyComposite
        default:
            return nil
        }
    }
}

/// A record of planning and lowering decisions, for tests and benchmarks.
///
/// Internal on purpose: applications must not depend on which optimisation
/// was chosen. Runtime metrics belong to ``Hokusai/runtimeStatus``.
final class PlanTrace: @unchecked Sendable {
    enum Event: Equatable, Sendable {
        /// A source was opened; the label is its decode operation, scoped for layers.
        case sourceOpened(String)
        /// An operation was lowered into the native graph, in order.
        case operationLowered(String)
        /// An operation was skipped as a proven identity.
        case operationSkipped(String, PlannerRule)
        /// A previously built node was reused instead of rebuilt.
        case memoisationHit(String)
        /// The decoder was asked to shrink the source by this factor.
        case shrinkOnLoad(Int)
        /// The terminal sink: `memory <format>` or `file <format>`.
        case sinkSelected(String)
    }

    // Guarded by `lock`, which makes `@unchecked Sendable` sound.
    private let lock = NSLock()
    private var recorded: [Event] = []

    func record(_ event: Event) {
        lock.withLock { recorded.append(event) }
    }

    var events: [Event] { lock.withLock { recorded } }
}
