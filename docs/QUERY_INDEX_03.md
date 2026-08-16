# Query / Index 0.3 Design Contract

## Current status

The 0.3 query/index engine has an authoritative native scan path, a conservative persisted-index planner path, deterministic native sorting, and diagnostic benchmark evidence.

Implemented:

- `Box.query(BoxQuery)` performs one FRB call per query.
- Rust decodes the query once and evaluates committed native records.
- Dotted nested-field lookup is supported.
- Numeric comparison preserves signed/unsigned MessagePack integer precision.
- Native scans work for plaintext and encrypted boxes.
- Persisted named single-field scalar indexes exist in the `full` profile.
- Index creation/backfill/drop and primary mutation maintenance are transactionally coupled to redb writes.
- Planner eligibility includes scalar `equal`, `greaterThan`, `greaterThanOrEqual`, `lessThan`, `lessThanOrEqual`, and `between` predicates at the top level or underneath `AND` groups.
- Matching indexes may be combined by intersecting candidate key sets for `AND` groups.
- Nested indexed fields such as `profile.age` are planner-eligible when the persisted definition exactly matches the dotted field path.
- The complete original predicate is always re-evaluated against primary data before ordering/pagination.
- One `Box.query(...)` uses one redb `ReadTransaction` snapshot for index definitions, candidate entry ranges, fallback key enumeration, primary-record reads, and sort inputs.
- Queries without a safe usable index fall back to native scan within that same read snapshot.
- Deterministic `sortBy` supports ordered clauses, explicit null/missing placement, exact numeric semantics, lexical strings, and an ascending record-key tie-break.
- Pagination is applied after sorting when `sortBy` is present; the unsorted path retains deterministic key order and early pagination.
- Scan/index equivalence coverage exists for equality, nested range operators, inclusive `between`, multi-index AND intersection, and sorted execution.
- Encrypted boxes reject persisted index creation until a non-leaking representation exists; native scan remains supported.
- Reduced profiles reject boxes that already contain persisted index definitions.
- Diagnostic benchmarks compare scan vs indexed equality, range, AND intersection, and sorted-range workloads.

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
  sortBy: List<QuerySort>
  limit: int?
  offset: int

QueryFilter
  QueryComparison
  QueryGroup.and(...)
  QueryGroup.or(...)

QuerySort
  field: dotted path
  direction: ascending | descending
  nulls: first | last
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

Indexes are named single-field scalar indexes:

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

Range operators accept ordered numeric or string scalar bounds.

Planner extraction is allowed at the top level and recursively through `AND` groups. The planner deliberately does not descend into `OR` groups because narrowing by only some OR branches could remove valid results.

`notEqual`, `isNull`, and `isNotNull` remain scan-backed.

## Planner selection policy

Candidate extraction and persisted-index selection are intentionally separate internal steps. Selection matches candidate fields to persisted definitions by exact dotted field path. Missing definitions are ignored, allowing a usable subset of an `AND` group to narrow the query. Multiple usable candidates remain eligible for intersection. If duplicate persisted index definitions target the same field, selection deterministically chooses the lexicographically smallest index name. If no candidate has a matching persisted definition, execution falls back to native scan.

Unit tests cover exact-field selection, partial-index AND selection, multi-index AND selection, deterministic duplicate-field choice, empty-selection fallback, OR extraction fallback, and filtering of non-indexable AND members. This is internal hardening only; no additional public API is required.

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
  -> bound redb iteration to that index name
  -> decode persisted scalar component
  -> compare scalar with the same comparator used by the query engine
  -> collect matching record keys
```

A future scalar-level redb range-seek optimization requires an order-preserving scalar encoding or equivalent proven ordering contract plus rebuild/migration semantics. Raw MessagePack numeric bytes are not sufficient by themselves.

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
  -> read primary records from the same snapshot
  -> decrypt if needed
  -> evaluate the complete original predicate
  -> if sortBy is empty:
       deterministic record-key order + efficient offset/limit
  -> else:
       collect all matches
       validate/extract sort values
       semantic multi-clause sort
       explicit null/missing placement
       ascending record-key tie-break
       offset / limit after sort
  -> return matching key + payload records
```

The index is candidate narrowing only. It is never final truth and does not satisfy ORDER BY.

## Scan/index/sort equivalence gate

Equivalence is required for every planner-eligible operator and for sorted planner execution.

Current integration coverage verifies:

1. A query before index creation executes through scan.
2. The exact same query after index creation returns the same ordered results.
3. Nested `profile.age` indexes match scan semantics for `>`, `>=`, `<`, `<=`, and inclusive `between`.
4. An AND query with indexes on both `status` and `profile.age` returns the same results after candidate-set intersection.
5. Transactional indexed-field mutation changes planner results correctly.
6. Reopen preserves index definitions.
7. Encrypted boxes continue to use scan and reject persisted index creation.
8. Sorting occurs before pagination.
9. Missing fields and null values share one explicit nullish bucket.
10. Descending direction does not reverse explicit null placement.
11. Large integer ordering remains exact across signed/unsigned boundaries.
12. Mixed numeric/string sort domains and NaN are rejected.
13. Record key ascending is the final deterministic tie-break.
14. Scan and indexed execution return the same sorted results.

Future planner or sorting rules must add equivalent scan-vs-index coverage first.

## Numeric correctness

MessagePack integers are compared exactly across signed and unsigned domains. Large integers above the exact `f64` range must not become equal due to float rounding. Mixed integer/float comparisons use explicit boundary handling.

The same comparator semantics are reused for persisted range candidate matching and numeric sorting.

## Encryption semantics

Encrypted boxes may use native scan query and deterministic sorting after decrypting values from the same read snapshot. Persisted index creation is rejected because plaintext-derived scalar keys would leak indexed values. Plaintext-to-encrypted migration is rejected while persisted index definitions exist.

## Reduced-profile safety

`minimal` and `encryption` builds do not maintain persisted indexes and therefore reject opening boxes that already contain index definitions. Explicit rejection prevents stale derived state.

## Diagnostic benchmark evidence

`benchmark/test/query_index_benchmark_test.dart` measures equality, range, multi-index AND, and sorted-range workloads at 100, 1,000, and 5,000 records with setup/backfill outside the timed region.

The 2026-08-16 shared-runner baseline showed indexed execution with lower medians than scan in all measured cases. This supports retaining candidate narrowing but is not sufficient evidence for a storage-format migration to order-preserving scalar bytes. Shared-runner timings are diagnostic, not an SLA or release threshold.

## Binary-size and SDK policy

Cross-commit binary-size regression policy remains separate from query/index work. Same-commit profile reproducibility is already a CI gate. Dart 3.13 recorded-use/native tree shaking remains deferred. The package floor remains Dart >= 3.4.0 and Flutter >= 3.22.0.

## Completed 0.3 sequence

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
15. Pure deterministic planner-selection step with direct selection/fallback unit coverage.
16. Public `sortBy` contract and deterministic native execution.
17. Sort-before-pagination, null/missing, numeric precision, error-domain, and scan/index sort-equivalence tests.
18. Focused query/index diagnostic benchmark matrix.
19. Point-read diagnosis kept separate from query/index storage-format decisions.

## Deferred beyond 0.3

The following are intentionally not required for 0.3 closure:

- encrypted persisted indexes;
- versioned order-preserving scalar encoding and true scalar-level redb range seeks;
- index-backed ORDER BY;
- composite/unique/full-text/custom-collation indexes;
- cross-commit native binary-size thresholds;
- Dart 3.13 recorded-use/native tree shaking.

## Correctness rules

- Query results come from committed native truth.
- Primary `data` is authoritative; indexes are derived state.
- The planner may narrow candidates but may not skip full predicate re-evaluation.
- Scan and indexed execution must be logically equivalent.
- Sorting is semantic and deterministic; pagination follows sorting when `sortBy` is present.
- Explicit null placement is independent of sort direction.
- Record key ascending is always the final sort tie-break.
- Reduced profiles reject unsafe persisted-index boxes.
- Encrypted indexed fields must not leak through plaintext persisted index keys.
- Raw MessagePack numeric byte ordering must not be used as query numeric ordering.
