from pathlib import Path


def append_once(path: str, marker: str, section: str) -> None:
    file = Path(path)
    text = file.read_text()
    if marker in text:
        return
    if not text.endswith("\n"):
        text += "\n"
    file.write_text(text + "\n" + section.strip() + "\n")


def replace_if_present(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old in text:
        file.write_text(text.replace(old, new, 1))


append_once(
    "docs/CODE_WALKTHROUGH.md",
    "## 20. Deterministic native query sorting",
    r'''
## 20. Deterministic native query sorting

`BoxQuery` now accepts an ordered `sortBy` list. Public sort clauses are represented by `QuerySort`, `QuerySortDirection`, and `QueryNullOrder`; they are serialized inside the existing opaque MessagePack query payload, so the FRB function shape does not change.

Sorted execution deliberately separates filtering/planning from ordering:

```text
Box.query(sortBy: ...)
  -> planner discovers candidate keys as before
  -> one redb read snapshot
  -> primary records are re-read and full predicates re-evaluated
  -> extract ordered sort values from nested dotted fields
  -> validate non-null values for each sort field use one compatible ordered domain
  -> stable semantic comparison across sort clauses
  -> record key is the final deterministic tie-break
  -> offset / limit are applied after sorting
```

Numeric ordering reuses the exact query comparator and therefore preserves signed/unsigned integer precision, including values above 2^53. String ordering is lexical. Missing fields and explicit null values form one nullish category whose placement is controlled independently with `QueryNullOrder.first` or `.last`; sort direction does not invert explicit null placement.

A sort field rejects unsupported non-null values, NaN, and mixtures of numeric and string values in the same ordered column. This makes ordering behavior explicit instead of relying on an implicit cross-type total order.

The unsorted path keeps its existing deterministic record-key order and early pagination behavior. The sorted path must collect all predicate matches visible in the same redb snapshot before applying ordering and pagination.

`rust/tests/query_index.rs` verifies order-before-pagination, nested sort fields, null/missing placement, mixed-type rejection, large-integer precision, deterministic key tie-breaking, and exact scan/index result equivalence. `make query-sort-test` runs the focused Dart contract and Rust integration coverage.
''',
)
replace_if_present(
    "docs/CODE_WALKTHROUGH.md",
    "2. define explicit `sortBy` semantics as a separate public API decision;",
    "2. preserve deterministic `sortBy` semantics and scan/index equivalence as query execution invariants;",
)

append_once(
    "docs/QUERY_INDEX_03.md",
    "## Explicit query sorting",
    r'''
## Explicit query sorting

`BoxQuery.sortBy` is an ordered list of `QuerySort` clauses. Each clause names an exact dotted field path, an ascending/descending direction, and explicit null placement (`first` or `last`). Sorting occurs after candidate discovery and authoritative predicate re-evaluation but before `offset`/`limit`.

Ordering domains are intentionally strict: non-null values for one sort field must be all numeric or all strings. Numeric comparison uses the same exact signed/unsigned/float semantics as query predicates and does not coerce integers through `f64`. NaN and unsupported structured/bool values are rejected for ordered sorting. Missing and explicit null are one nullish category. The primary record key is the final deterministic tie-break after all user clauses compare equal.

Index use does not change sort semantics: the same sorted query before and after matching index creation must return the exact same ordered records. Current persisted indexes narrow candidates only; they are not claimed to satisfy sort order and no raw MessagePack scalar byte ordering is used as an ordering shortcut.
''',
)

append_once(
    "docs/PROJECT_HANDOFF.md",
    "### Query sort milestone completed",
    r'''
### Query sort milestone completed

The public declarative query contract now includes deterministic multi-clause `sortBy` via `QuerySort`, `QuerySortDirection`, and `QueryNullOrder` without changing the FRB function signature. Native execution sorts authoritative predicate matches inside the same redb read snapshot before pagination, supports nested dotted fields, exact numeric ordering, lexical strings, explicit null placement, and record-key tie-breaking. Mixed incompatible non-null sort domains, unsupported ordered values, and NaN are rejected explicitly. Focused Dart/Rust coverage is available through `make query-sort-test`, including scan/index ordered-result equivalence.

Next query/index work should benchmark the now-stable planner/sort execution before introducing a new persisted scalar representation. Scalar-level redb range seeks or index-order sort satisfaction remain deferred until an order-preserving encoding contract and migration/rebuild semantics are justified.
''',
)

append_once(
    "README.md",
    "### Deterministic query sorting",
    r'''
### Deterministic query sorting

Declarative queries can apply ordered sort clauses before pagination:

```dart
final rows = await box.query(
  BoxQuery(
    where: QueryComparison(
      field: 'status',
      operator: QueryOperator.equal,
      value: 'active',
    ),
    sortBy: [
      QuerySort(
        field: 'profile.age',
        direction: QuerySortDirection.descending,
        nulls: QueryNullOrder.last,
      ),
      QuerySort(field: 'name'),
    ],
    limit: 20,
  ),
);
```

Sort fields support nested dotted paths. Ordered non-null values must be consistently numeric or consistently strings per field; null/missing placement is explicit, and record key ordering is the deterministic final tie-break. Persisted indexes currently narrow query candidates but do not claim to satisfy requested sort order.
''',
)
