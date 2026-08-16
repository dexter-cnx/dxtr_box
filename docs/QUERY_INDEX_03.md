# Query / Index 0.3 Design Contract

## Current status

The 0.3 query/index engine has an authoritative native scan path plus a conservative persisted-index planner path.

Implemented:

- `Box.query(BoxQuery)` performs one FRB call per query.
- Rust decodes the query once and evaluates committed native records.
- Dotted nested-field lookup is supported.
- Numeric comparison preserves signed/unsigned MessagePack integer precision.
- Native scans work for plaintext and encrypted boxes.
- Persisted named single-field scalar indexes exist in the `full` profile.
- Index creation/backfill/drop and primary mutation maintenance are transactionally coupled to redb writes.
- Planner eligibility now includes scalar `equal`, `greaterThan`, `greaterThanOrEqual`, `lessThan`, `lessThanOrEqual`, and `between` predicates at the top level or underneath `AND` groups.
- Matching indexes may be combined by intersecting candidate key sets for `AND` groups.
- Nested indexed fields such as `profile.age` are planner-eligible when the persisted definition exactly matches the dotted field path.
- The complete original predicate is always re-evaluated against primary data before ordering/pagination.
- One `Box.query(...)` now uses one redb `ReadTransaction` snapshot for index definitions, candidate entry ranges, fallback key enumeration, and primary-record reads.
- Queries without a safe usable index fall back to native scan within that same read snapshot.
- Scan/index equivalence coverage exists for equality, nested range operators, inclusive `between`, and multi-index AND intersection.
- Encrypted boxes reject persisted index creation until a non-leaking representation exists; native scan remains supported.
- Reduced profiles reject boxes that already contain persisted index definitions.

## Public profile contract

Exactly three public native product profiles remain:

```text
minimal     = CRUD + lifecycle + native watch
encryption  = minimal + encrypted create/open/read/write
full        = encryption + maintenance + query/index implementation
```

Do not add a fourth public query profile.

## Public query model

```text
BoxQuery
  where: QueryFilter
  limit: int?
  offset: int

QueryFilter
  QueryComparison
  QueryGroup.and(...)
  QueryGroup.or(...)
```

Supported comparison operators:

```text
equal
notEqual
greaterThan
greaterThanOrEqual
lessThan
lessThanOrEqual
between
isNull
isNotNull
```

Fields may be dotted paths such as `status`, `profile.age`, and `address.country`.

## Persisted index contract

Initial indexes are named single-field scalar indexes:

```dart
IndexDefinition(
  name: 'by-age',
  field: 'profile.age',
)
```

Constraints:

- one dotted field path per index;
- scalar index keys only;
- no composite or unique indexes;
- no list expansion;
- no full text;
- no custom collation;
- persisted index creation is plaintext-only.

Primary `data` is authoritative. Secondary indexes are derived state.

redb layout:

```text
data
meta
index_definitions
index_entries
```

## Planner eligibility

The planner may narrow candidates for these operators when the query bound is index-compatible and a persisted index exists for the exact field:

```text
equal
greaterThan
greaterThanOrEqual
lessThan
lessThanOrEqual
between
```

Range operators currently accept ordered numeric or string scalar bounds.

Planner extraction is allowed at the top level and recursively through `AND` groups. The planner deliberately does not descend into `OR` groups because narrowing by only some OR branches could remove valid results.

`notEqual`, `isNull`, and `isNotNull` remain scan-backed.

## Multi-index AND planning

For an AND query with multiple usable persisted indexes, each indexed predicate produces a candidate record-key set. Sets are sorted by cardinality and intersected starting from the smallest.

```text
AND
  status == active      -> by-status candidate set
  profile.age >= 18     -> by-age candidate set

intersection
  -> candidate record keys
  -> current primary reads
  -> full predicate recheck
```

A missing index does not make the query fail. Remaining usable indexes may still narrow the candidate set, and any non-indexed predicates are evaluated against primary data during the mandatory recheck.

## Persisted entry representation

Index entries use length-prefixed binary components:

```text
[index-name length][index-name bytes]
[scalar length][MessagePack scalar bytes]
[record-key length][record-key UTF-8 bytes]
```

This avoids delimiter ambiguity.

## Range lookup correctness rule

MessagePack scalar bytes are not treated as a general sort-preserving numeric representation. In particular, lexicographic byte order must not be assumed to equal query numeric order across MessagePack integer encodings.

Therefore the current range planner is correctness-first:

```text
matching index definition
  -> inspect entries belonging to that index
  -> decode persisted scalar component
  -> compare scalar with the same comparator used by the query engine
  -> collect matching record keys
```

A future redb range-seek optimization requires an order-preserving scalar encoding or equivalent proven ordering contract. Raw MessagePack numeric bytes are not sufficient by themselves.

## Execution shape

```text
Box.query(BoxQuery)
  -> one FRB call
  -> query::decode_query once
  -> open one redb ReadTransaction snapshot
  -> index::candidate_keys(read, filter)
       -> index definitions + usable candidate sets from the same snapshot
       -> optional AND intersection
       -> None when scan is required
  -> fallback key enumeration from the same snapshot when needed
  -> sort + deduplicate candidate keys
  -> read primary record from the same snapshot
  -> decrypt if needed
  -> evaluate the complete original predicate
  -> deterministic record-key ordering
  -> apply offset / limit
  -> return matching key + payload records
```

The index is candidate narrowing only. It is never final truth.

## Scan/index equivalence gate

Equivalence is required for every planner-eligible operator.

Current integration coverage verifies:

1. A query before index creation executes through scan.
2. The exact same query after index creation returns the same ordered results.
3. Nested `profile.age` indexes match scan semantics for `>`, `>=`, `<`, `<=`, and inclusive `between`.
4. An AND query with indexes on both `status` and `profile.age` returns the same results after candidate-set intersection.
5. Transactional indexed-field mutation changes planner results correctly.
6. Reopen preserves index definitions.
7. Encrypted boxes continue to use scan and reject persisted index creation.

Future planner rules must add equivalent scan-vs-index coverage first.

## Numeric correctness

MessagePack integers are compared exactly across signed and unsigned domains. Large integers above the exact `f64` range must not become equal due to float rounding. Mixed integer/float comparisons use explicit boundary handling.

The same comparator semantics are reused for persisted range candidate matching.

## Encryption semantics

Encrypted boxes may use native scan query. Persisted index creation is rejected because plaintext-derived scalar keys would leak indexed values. Plaintext-to-encrypted migration is rejected while persisted index definitions exist.

## Reduced-profile safety

`minimal` and `encryption` builds do not maintain persisted indexes and therefore reject opening boxes that already contain index definitions. Explicit rejection prevents stale derived state.

## Binary-size and SDK policy

Cross-commit binary-size regression policy remains separate from query/index work. Dart 3.13 recorded-use/native tree shaking remains deferred. The package floor remains Dart >= 3.4.0 and Flutter >= 3.22.0.

## Completed 0.3 planner sequence

1. Dart query/index AST and validation.
2. Stable native transport representation.
3. One-call native scan executor.
4. Persisted scalar index metadata and entries.
5. Transactional index maintenance.
6. Index lifecycle create/backfill/list/drop.
7. Equality planner.
8. Equality scan/index equivalence.
9. Reduced-profile persisted-index safety guard.
10. Nested range planner for `>`, `>=`, `<`, `<=`, and `between`.
11. Multi-index candidate intersection for AND groups.
12. Range and intersection scan/index equivalence coverage.
13. Bounded index-name redb range iteration for lookup and drop cleanup.
14. Single-redb-read-transaction query execution across planner/fallback/primary reads.

## Next

1. Add planner diagnostics/selection tests only if they improve maintainability without expanding public API prematurely.
2. Define `sortBy` as a separate public API contract.
3. Add query/index benchmark scenarios now that bounded index iteration and single-snapshot query execution are stable.
4. Design an order-preserving scalar encoding only if benchmark evidence justifies scalar-level redb range seek.

## Correctness rules

- Query results come from committed native truth.
- Primary `data` is authoritative; indexes are derived state.
- The planner may narrow candidates but may not skip full predicate re-evaluation.
- Scan and indexed execution must be logically equivalent.
- Pagination occurs after deterministic key ordering until an explicit sort contract supersedes it.
- Reduced profiles reject unsafe persisted-index boxes.
- Encrypted indexed fields must not leak through plaintext persisted index keys.
- Raw MessagePack numeric byte ordering must not be used as query numeric ordering.

## Bounded index-name range optimization

Persisted index lookup and `dropIndex` cleanup now use a redb half-open range bounded by the encoded index-name prefix and its lexicographic successor. This skips unrelated persisted indexes at the storage iterator level while preserving the existing scalar comparison contract.

The optimization does **not** use MessagePack scalar bytes as numeric range bounds. Candidate scalar components are still decoded and evaluated with the same exact comparator used by the authoritative query engine. Scan/index equivalence therefore remains unchanged.

