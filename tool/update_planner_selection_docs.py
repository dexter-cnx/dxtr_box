from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        if new in text:
            return
        raise SystemExit(f'missing expected anchor in {path}: {old[:120]!r}')
    p.write_text(text.replace(old, new, 1))

replace_once(
    'docs/CODE_WALKTHROUGH.md',
    '''Nested dotted fields such as `profile.age` are eligible when a persisted index exists for that exact field path.\n\n## 9. Persisted index representation''',
    '''Nested dotted fields such as `profile.age` are eligible when a persisted index exists for that exact field path.\n\nPlanner selection is a separate pure internal step in `rust/src/index.rs`. Candidate extraction determines what predicates are safe to index; selection matches those candidates to persisted definitions by exact field path. If several persisted indexes target the same field, the lexicographically smallest index name is chosen deterministically. Missing definitions are ignored, so an `AND` group may still narrow through the usable subset. An empty selection means native scan fallback. Unit coverage locks these choices independently from storage lookup.\n\n## 9. Persisted index representation''',
)
replace_once(
    'docs/CODE_WALKTHROUGH.md',
    '''1. keep the implemented bounded index-name range and single-read-transaction query snapshot as execution invariants;\n2. add planner diagnostics/selection tests if they materially improve maintainability;\n3. define/order-preserving scalar encoding only if scalar-level redb range seek is justified by benchmarks;\n4. define explicit `sortBy` semantics as a separate public API decision;\n5. add query/index benchmark scenarios only after execution semantics remain stable;''',
    '''1. keep bounded index-name ranges, deterministic planner selection, and the single-read-transaction query snapshot as execution invariants;\n2. define explicit `sortBy` semantics as a separate public API decision;\n3. add focused query/index benchmark scenarios now that planner selection and execution semantics are stable;\n4. define an order-preserving scalar encoding only if scalar-level redb range seek is justified by benchmarks;''',
)

replace_once(
    'docs/QUERY_INDEX_03.md',
    '''`notEqual`, `isNull`, and `isNotNull` remain scan-backed.\n\n## Multi-index AND planning''',
    '''`notEqual`, `isNull`, and `isNotNull` remain scan-backed.\n\n## Planner selection policy\n\nCandidate extraction and persisted-index selection are intentionally separate internal steps. Selection matches candidate fields to persisted definitions by exact dotted field path. Missing definitions are ignored, allowing a usable subset of an `AND` group to narrow the query. Multiple usable candidates remain eligible for intersection. If duplicate persisted index definitions target the same field, selection deterministically chooses the lexicographically smallest index name. If no candidate has a matching persisted definition, execution falls back to native scan.\n\nUnit tests cover exact-field selection, partial-index AND selection, multi-index AND selection, deterministic duplicate-field choice, empty-selection fallback, OR extraction fallback, and filtering of non-indexable AND members. This is internal hardening only; no Dart or FRB API is added.\n\n## Multi-index AND planning''',
)
replace_once(
    'docs/QUERY_INDEX_03.md',
    '''14. Single-redb-read-transaction query execution across planner/fallback/primary reads.''',
    '''14. Single-redb-read-transaction query execution across planner/fallback/primary reads.\n15. Pure deterministic planner-selection step with direct selection/fallback unit coverage.''',
)
replace_once(
    'docs/QUERY_INDEX_03.md',
    '''1. Add planner diagnostics/selection tests only if they improve maintainability without expanding public API prematurely.\n2. Define `sortBy` as a separate public API contract.\n3. Add query/index benchmark scenarios now that bounded index iteration and single-snapshot query execution are stable.\n4. Design an order-preserving scalar encoding only if benchmark evidence justifies scalar-level redb range seek.''',
    '''1. Define `sortBy` as a separate public API contract.\n2. Add focused query/index benchmark scenarios now that bounded iteration, deterministic planner selection, and single-snapshot execution are stable.\n3. Design an order-preserving scalar encoding only if benchmark evidence justifies scalar-level redb range seek.''',
)

replace_once(
    'docs/PROJECT_HANDOFF.md',
    '''## Current snapshot — 0.3 single-snapshot query execution\n\nMain contains the native query/index foundation, equality/range planning, nested indexes, AND intersection, and bounded index-name redb iteration. Current branch:\n\n```text\nfeature/0.3-query-read-transaction\n```\n\nrefactors native query execution so planner lookup, fallback key enumeration, and primary reads share one redb `ReadTransaction`, without changing the public Dart API or FRB shape.''',
    '''## Current snapshot — 0.3 planner selection hardening\n\nMain contains the native query/index foundation, equality/range planning, nested indexes, AND intersection, bounded index-name redb iteration, and single-snapshot query execution. Current branch:\n\n```text\nfeature/0.3-planner-selection-tests\n```\n\nhardens the internal planner by separating persisted-index selection from candidate extraction and adding direct deterministic selection/fallback tests, without changing the public Dart API or FRB shape.''',
)
replace_once(
    'docs/PROJECT_HANDOFF.md',
    '''3. Add planner diagnostics/selection tests only if useful for maintainability.\n4. Define an explicit public `sortBy` contract separately.\n5. Add query/index benchmark scenarios now that core execution semantics are stable.''',
    '''3. Completed: deterministic pure planner-selection step with direct selection/fallback tests.\n4. Define an explicit public `sortBy` contract separately.\n5. Add focused query/index benchmark scenarios now that planner and execution semantics are stable.''',
)
replace_once(
    'docs/PROJECT_HANDOFF.md',
    '''The next architecture work is no longer read-transaction plumbing: one native query now observes one redb read snapshot across planner, fallback, and primary reads. Next candidates are planner diagnostics, an explicit sort contract, and benchmark scenarios; scalar-level redb seeks still require a separately proven order-preserving scalar encoding.''',
    '''The planner now also has a pure deterministic selection step with direct tests for exact-field matching, partial/multi-index AND behavior, duplicate-field choice, and fallback. Next candidates are an explicit sort contract and focused benchmark scenarios; scalar-level redb seeks still require a separately proven order-preserving scalar encoding.''',
)
