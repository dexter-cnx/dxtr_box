from pathlib import Path

replacements = {
    'docs/CODE_WALKTHROUGH.md': [
        (
            'The current correctness-first implementation filters the index table by encoded prefix; a more direct redb range implementation can follow without changing semantics.',
            'Candidate lookup now uses a bounded redb range over the encoded index-name prefix, so unrelated indexes are skipped at the storage iterator level. Within that bounded range, scalar MessagePack values are still decoded and compared with the query engine comparator; raw MessagePack byte ordering is never treated as numeric ordering.'
        ),
        (
            '3. consider redb range-based index lookup optimization;\n4. consider one-read-transaction native scan execution;',
            '3. keep the implemented redb index-name prefix range while designing any future order-preserving scalar encoding separately;\n4. consider one-read-transaction native scan execution;'
        ),
    ],
    'docs/QUERY_INDEX_03.md': [
        (
            'This slice prioritizes correctness. Entry lookup currently iterates the index table and filters by the encoded prefix rather than introducing a more aggressive redb range implementation. Range-level optimization can follow after planner semantics are stable.',
            'Index entry lookup now uses a redb range bounded by the encoded index-name prefix, avoiding a full `index_entries` table scan when one persisted index is selected. Scalar matching inside that range remains correctness-first: MessagePack scalar components are decoded and compared with the same query comparator. The implementation still does not use raw MessagePack scalar bytes as numeric range bounds.'
        ),
        (
            '13. Improve index lookup from table-prefix filtering to an efficient redb range strategy where semantics remain identical.\n14. Consider one-redb-read-transaction native scan execution as a separate architecture/performance improvement.',
            '13. Completed: bound index lookup and drop cleanup with redb index-name prefix ranges while preserving scalar comparison semantics.\n14. Consider one-redb-read-transaction native scan execution as a separate architecture/performance improvement.'
        ),
    ],
    'docs/PROJECT_HANDOFF.md': [
        (
            '## Current snapshot — 0.3 range-capable query planner\n\nMain already contains the native query/index foundation and first persisted-index equality planner. Current branch:\n\n```text\nfeature/0.3-range-index-planner\n```\n\nextends the internal planner without changing the public Dart API or FRB shape.',
            '## Current snapshot — 0.3 range-capable query planner\n\nMain contains the native query/index foundation, equality/range planner, nested-field indexes, and multi-index AND intersection. Current branch:\n\n```text\nfeature/0.3-index-prefix-range\n```\n\noptimizes persisted-index lookup without changing the public Dart API, FRB shape, or scalar comparison semantics.'
        ),
        (
            'Current correctness-first path:\n\n```text\nmatching index definition\n  -> inspect entries for that index\n  -> decode scalar component\n  -> compare with query engine\'s exact comparator\n  -> collect matching record keys\n```\n\nA future efficient redb range seek requires an order-preserving scalar encoding or equivalent proven ordering contract.',
            'Current correctness-first path:\n\n```text\nmatching index definition\n  -> compute encoded index-name prefix bounds\n  -> redb range only over entries for that index\n  -> decode scalar component\n  -> compare with query engine\'s exact comparator\n  -> collect matching record keys\n```\n\n`dropIndex` cleanup uses the same bounded index-name range. A future scalar-level redb range seek still requires an order-preserving scalar encoding or equivalent proven ordering contract.'
        ),
        (
            '1. Improve persisted-index lookup efficiency without relying on raw MessagePack numeric byte ordering.\n2. Consider one-redb-read-transaction query execution after planner correctness is stable.',
            '1. Completed: bound persisted-index lookup/drop cleanup to the selected index-name range without relying on raw MessagePack numeric byte ordering.\n2. Consider one-redb-read-transaction query execution after planner correctness is stable.'
        ),
    ],
    'README.md': [
        (
            'The planner is deliberately conservative in this slice. It may use persisted indexes for scalar equality and ordered range predicates at the top level or underneath an `AND` group, including nested dotted fields. Multiple usable `AND` indexes are intersected. Indexes only narrow candidate record keys: the normal predicate engine still re-evaluates every candidate, then applies deterministic key ordering and pagination. `OR`-driven narrowing, `notEqual`, and null-specific predicates remain scan-backed.',
            'The planner is deliberately conservative in this slice. It may use persisted indexes for scalar equality and ordered range predicates at the top level or underneath an `AND` group, including nested dotted fields. Multiple usable `AND` indexes are intersected. Indexes only narrow candidate record keys: the normal predicate engine still re-evaluates every candidate, then applies deterministic key ordering and pagination. Persisted entry lookup is bounded by the selected index-name using redb range iteration, while scalar range matching still decodes MessagePack values and uses the query comparator rather than raw byte ordering. `OR`-driven narrowing, `notEqual`, and null-specific predicates remain scan-backed.'
        ),
    ],
}

for filename, edits in replacements.items():
    path = Path(filename)
    text = path.read_text()
    for old, new in edits:
        if old not in text:
            raise SystemExit(f'missing expected text in {filename}: {old[:80]!r}')
        text = text.replace(old, new, 1)
    path.write_text(text)
