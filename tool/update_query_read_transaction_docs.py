from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        if new in text:
            return
        raise SystemExit(f'missing expected anchor in {path}: {old[:100]!r}')
    p.write_text(text.replace(old, new, 1))

replace_once(
    'docs/CODE_WALKTHROUGH.md',
    '''  -> query::decode_query once\n  -> index::candidate_keys(filter)\n       -> Some(keys) for usable equality/range index candidates\n       -> None when scan is required\n  -> sort + deduplicate candidate keys\n  -> db::get current primary payload for each candidate\n  -> decrypt if required''',
    '''  -> query::decode_query once\n  -> open one redb ReadTransaction snapshot\n  -> index::candidate_keys(read, filter)\n       -> index definitions + entry ranges from the same snapshot\n       -> Some(keys) for usable equality/range index candidates\n       -> None when scan is required\n  -> fallback key enumeration from the same snapshot when needed\n  -> sort + deduplicate candidate keys\n  -> primary payload reads from the same snapshot\n  -> decrypt if required''',
)
replace_once(
    'docs/CODE_WALKTHROUGH.md',
    '''The planner never treats persisted index membership as final truth. Every candidate is re-read from committed primary data and re-evaluated with the complete original predicate.''',
    '''The planner never treats persisted index membership as final truth. Every candidate is re-read from committed primary data and re-evaluated with the complete original predicate. Candidate discovery and primary-record reads now share one redb read transaction, so a single query observes one consistent redb snapshot instead of composing several independently opened read snapshots.''',
)
replace_once(
    'docs/CODE_WALKTHROUGH.md',
    '''1. improve persisted-index lookup efficiency without relying on raw MessagePack numeric byte ordering;\n2. consider a one-redb-read-transaction query execution path;\n3. add planner diagnostics/selection tests if they materially improve maintainability;''',
    '''1. keep the implemented bounded index-name range and single-read-transaction query snapshot as execution invariants;\n2. add planner diagnostics/selection tests if they materially improve maintainability;\n3. define/order-preserving scalar encoding only if scalar-level redb range seek is justified by benchmarks;''',
)

replace_once(
    'docs/QUERY_INDEX_03.md',
    '''- The complete original predicate is always re-evaluated against current primary data before ordering/pagination.\n- Queries without a safe usable index fall back to native scan.''',
    '''- The complete original predicate is always re-evaluated against primary data before ordering/pagination.\n- One `Box.query(...)` now uses one redb `ReadTransaction` snapshot for index definitions, candidate entry ranges, fallback key enumeration, and primary-record reads.\n- Queries without a safe usable index fall back to native scan within that same read snapshot.''',
)
replace_once(
    'docs/QUERY_INDEX_03.md',
    '''  -> query::decode_query once\n  -> index::candidate_keys(filter)\n       -> usable index candidate sets\n       -> optional AND intersection\n       -> None when scan is required\n  -> sort + deduplicate candidate keys\n  -> read current primary record\n  -> decrypt if needed''',
    '''  -> query::decode_query once\n  -> open one redb ReadTransaction snapshot\n  -> index::candidate_keys(read, filter)\n       -> index definitions + usable candidate sets from the same snapshot\n       -> optional AND intersection\n       -> None when scan is required\n  -> fallback key enumeration from the same snapshot when needed\n  -> sort + deduplicate candidate keys\n  -> read primary record from the same snapshot\n  -> decrypt if needed''',
)
replace_once(
    'docs/QUERY_INDEX_03.md',
    '''12. Range and intersection scan/index equivalence coverage.''',
    '''12. Range and intersection scan/index equivalence coverage.\n13. Bounded index-name redb range iteration for lookup and drop cleanup.\n14. Single-redb-read-transaction query execution across planner/fallback/primary reads.''',
)
replace_once(
    'docs/QUERY_INDEX_03.md',
    '''1. Improve persisted-index lookup efficiency without relying on raw MessagePack numeric byte ordering.\n2. Consider one-redb-read-transaction query execution.\n3. Add planner diagnostics/selection tests only if they improve maintainability without expanding public API prematurely.\n4. Define `sortBy` as a separate public API contract.\n5. Add query/index benchmark scenarios only after semantic paths remain stable.''',
    '''1. Add planner diagnostics/selection tests only if they improve maintainability without expanding public API prematurely.\n2. Define `sortBy` as a separate public API contract.\n3. Add query/index benchmark scenarios now that bounded index iteration and single-snapshot query execution are stable.\n4. Design an order-preserving scalar encoding only if benchmark evidence justifies scalar-level redb range seek.''',
)

replace_once(
    'docs/PROJECT_HANDOFF.md',
    '''## Current snapshot — 0.3 range-capable query planner\n\nMain already contains the native query/index foundation and first persisted-index equality planner. Current branch:\n\n```text\nfeature/0.3-range-index-planner\n```\n\nextends the internal planner without changing the public Dart API or FRB shape.''',
    '''## Current snapshot — 0.3 single-snapshot query execution\n\nMain contains the native query/index foundation, equality/range planning, nested indexes, AND intersection, and bounded index-name redb iteration. Current branch:\n\n```text\nfeature/0.3-query-read-transaction\n```\n\nrefactors native query execution so planner lookup, fallback key enumeration, and primary reads share one redb `ReadTransaction`, without changing the public Dart API or FRB shape.''',
)
replace_once(
    'docs/PROJECT_HANDOFF.md',
    '''  -> query::decode_query once\n  -> index::candidate_keys\n       -> equality/range candidate sets\n       -> optional AND intersection\n       -> None when scan is required\n  -> sort + deduplicate candidate keys\n  -> read current primary records\n  -> decrypt if required''',
    '''  -> query::decode_query once\n  -> open one redb ReadTransaction snapshot\n  -> index::candidate_keys(read, filter)\n       -> definitions + equality/range candidate sets from the same snapshot\n       -> optional AND intersection\n       -> None when scan is required\n  -> fallback key enumeration from the same snapshot when needed\n  -> sort + deduplicate candidate keys\n  -> read primary records from the same snapshot\n  -> decrypt if required''',
)
replace_once(
    'docs/PROJECT_HANDOFF.md',
    '''1. Improve persisted-index lookup efficiency without relying on raw MessagePack numeric byte ordering.\n2. Consider one-redb-read-transaction query execution after planner correctness is stable.\n3. Add planner diagnostics/selection tests only if useful for maintainability.\n4. Define an explicit public `sortBy` contract separately.\n5. Add query/index benchmark scenarios after semantic paths remain stable.''',
    '''1. Completed: bounded persisted-index lookup/drop cleanup by index-name range.\n2. Completed: one-redb-read-transaction query execution for planner/fallback/primary reads.\n3. Add planner diagnostics/selection tests only if useful for maintainability.\n4. Define an explicit public `sortBy` contract separately.\n5. Add query/index benchmark scenarios now that core execution semantics are stable.''',
)
replace_once(
    'docs/PROJECT_HANDOFF.md',
    '''After this slice, the next architecture candidate remains one-redb-read-transaction query execution, followed by explicit sort semantics and benchmark scenarios only after correctness remains stable.''',
    '''The next architecture work is no longer read-transaction plumbing: one native query now observes one redb read snapshot across planner, fallback, and primary reads. Next candidates are planner diagnostics, an explicit sort contract, and benchmark scenarios; scalar-level redb seeks still require a separately proven order-preserving scalar encoding.''',
)

replace_once(
    'README.md',
    '''- every candidate is still re-read and re-evaluated from primary committed data.''',
    '''- every candidate is still re-read and re-evaluated from primary data;\n- planner lookup, fallback key enumeration, and primary-record reads share one redb read transaction snapshot per native query.''',
)
replace_once(
    'README.md',
    '''For AND queries with several usable indexes, candidate key sets are intersected starting from the smallest set. The full original predicate is then re-evaluated against current primary data before deterministic ordering and pagination.''',
    '''For AND queries with several usable indexes, candidate key sets are intersected starting from the smallest set. The full original predicate is then re-evaluated against primary data before deterministic ordering and pagination. Candidate planning, fallback enumeration, and primary reads all use the same redb `ReadTransaction`, giving each native query a single consistent storage snapshot.''',
)
