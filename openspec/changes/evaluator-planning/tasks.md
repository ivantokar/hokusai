## 1. Planner

- [x] 1.1 `PlannerRule`, `PlannerOptions` (with `.reference`), pure `Planner.plan` (1:1, ordered)
- [x] 1.2 Identity rules: whole-turn rotation, empty composite
- [x] 1.3 Rebuild `ImagePlan` on identity-bearing immutable nodes

## 2. Lowering

- [x] 2.1 Per-evaluation memoisation by node identity; sequential sources excluded
- [x] 2.2 Skip planned identities during lowering
- [x] 2.3 Internal `PlanTrace`: sources, lowered/skipped operations, memo hits, terminal sink

## 3. Tests and docs

- [x] 3.1 Pure planner tests (order, identity rules, look-alikes, disabled rules)
- [x] 3.2 Reference-lowering equivalence for identity skipping and memoisation
- [x] 3.3 Order, analytical position, independent values, sequential, evaluation independence, sinks
- [x] 3.4 README and CHANGELOG
