# Query / Index 0.3 Design Contract

## Current status

The 0.3 query/index engine now has both an authoritative native scan path and a conservative persisted-index planner path.

Implemented:

- `Box.query(BoxQuery)` serializes the public Dart AST with `DxtrCodec` and performs one FRB call per query.
- Rust decodes the query once, evaluates comparisons/groups against committed native records, supports dotted nested-field lookup, and applies deterministic record-key ordering before pagination.
- Integer comparisons preserve signed/unsigned MessagePack precision instead of collapsing all numbers through `f64`.
- Native scans work for plaintext and encrypted boxes. Encrypted records are decrypted only inside the trusted native storage path.
- Persisted named scalar secondary-index definitions and entries exist in redb under the `full` profile.
- Index create/backfill/drop and primary mutation maintenance are transactionally coupled to redb writes.
- A conservative planner can use a matching persisted index for scalar `equal` predicates at the top level or underneath an `AND` group.
- Index-backed execution only narrows candidate record keys. The normal predicate evaluator always re-checks candidates before ordering/pagination.
- Queries without a safe planner candidate fall back to native scan.
- Scan/index equivalence coverage runs the same logical query before and after index creation and verifies identical result payloads and indexed-field mutation behavior.
- Encrypted boxes intentionally reject persisted index creation until a non-leaking encrypted-index representation is designed; native scan queries remain available.
- Plaintext -> encrypted migration is rejected while persisted index definitions exist.
- Reduced profiles reject opening a box that already contains persisted index definitions, preventing primary mutation without derived-index maintenance.

## Scope

0.3 introduces structured query and secondary-index capabilities without weakening storage, encryption, durability, lifecycle, SDK, or Cargo profile contracts.

The Dart AST remains execution-agnostic. Planner changes are internal native implementation details and must not alter normal query construction or logical results.

## Public profile contract

Exactly three public native product profiles remain:

```text
minimal     = CRUD + lifecycle + native watch
encryption  = minimal + encrypted create/open/read/write
full        = encryption + maintenance + query/index implementation
```

Do not add a fourth public query profile.

`full` may include internal optional dependencies required by query/index implementation. Reduced profiles retain the stable FRB symbol surface and fail explicitly for unavailable capabilities. Boxes containing persisted index definitions require `full` for safe mutation.

## Public naming policy

`Dxtr` is reserved for the product/root namespace such as `DxtrBox`. Feature-level public types use domain names:

```text
BoxQuery
QueryFilter
QueryComparison
QueryGroup
QueryOperator
QueryLogicalOperator
IndexDefinition
```

## Dart query model

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

Fields use dotted paths such as `status`, `profile.age`, and `address.country`.

## Persisted index contract

Initial indexes are named single-field scalar indexes:

```dart
IndexDefinition(
  name: 'by-status',
  field: 'status',
)
```

Current constraints:

- one indexed dotted field path per index;
- scalar index keys only;
- no composite indexes;
- no uniqueness contract;
- no full text;
- no list expansion;
- no custom collation;
- persisted index creation is plaintext-only.

Primary `data` remains authoritative. Secondary indexes are always derived state.

redb layout:

```text
data
meta
index_definitions   # name -> dotted field path
index_entries       # length-aware encoded index name + scalar + record key
```

Index mutation is transactionally coupled to primary mutation. A committed `put`, `putAll`, `delete`, `deleteAll`, or `clear` cannot leave persisted index state describing a different committed primary state.

## Planner contract

The first planner is intentionally conservative.

Planner-eligible narrowing currently means:

```text
QueryComparison(equal)
  where value is scalar
  and persisted index exists for the exact field

OR

QueryGroup.and([...])
  containing at least one such equality comparison
```

The planner deliberately does **not** use an equality predicate found only inside an `OR` group. It also does not yet use range, `between`, inequality, or null-specific operators for index narrowing.

Execution shape:

```text
Box.query(BoxQuery)
  -> one FRB call
  -> query::decode_query once
  -> planner inspects filter
  -> if safe matching persisted equality index exists:
       read candidate record keys from index_entries
     else:
       enumerate primary keys
  -> sort + deduplicate candidate keys
  -> read current primary record
  -> decrypt if needed
  -> evaluate the complete original predicate
  -> deterministic record-key ordering
  -> apply offset / limit
  -> return matching key + payload records
```

The index is never trusted as the final predicate result. Candidate re-evaluation protects semantics from planner broadening and keeps the primary table authoritative.

## Equality lookup representation

The persisted entry encoding uses length-prefixed binary components rather than delimiter concatenation:

```text
[index-name length][index-name bytes]
[scalar length][MessagePack scalar bytes]
[record-key length][record-key UTF-8 bytes]
```

For an eligible equality query the planner reconstructs the index-name + scalar prefix, finds matching derived entries, decodes record keys, and then re-checks primary records.

This slice prioritizes correctness. Entry lookup currently iterates the index table and filters by the encoded prefix rather than introducing a more aggressive redb range implementation. Range-level optimization can follow after planner semantics are stable.

## Scan/index equivalence

Equivalence is a release gate for every planner-eligible operator.

Current integration coverage proves:

1. Query without an index executes via native scan.
2. The exact same query after index creation returns the same ordered keys and payloads.
3. Changing an indexed field transactionally updates the index and changes planner results correctly.
4. Closing/reopening preserves index definitions.
5. Encrypted boxes continue to use scan because persisted index creation is rejected.

Any future planner eligibility expansion must add matching scan-vs-index equivalence tests before being considered complete.

## Numeric correctness

MessagePack integers are compared exactly across signed and unsigned integer domains. Large integers above the exact `f64` range must not become equal merely because both would round to the same float.

Mixed integer/float comparison handles finite bounds and infinities explicitly while preserving integer precision where possible.

## Encryption semantics

For encrypted boxes:

- primary payloads remain authenticated ciphertext at rest;
- native scan code may inspect decrypted MessagePack only inside the trusted storage path;
- persisted secondary index keys must not silently leak plaintext indexed values.

Therefore encrypted boxes reject persisted index creation. Native scan queries remain supported.

A plaintext box with persisted index definitions cannot be migrated to encrypted storage until encrypted-index representation and migration semantics are designed.

## Reduced-profile safety

`minimal` and `encryption` builds do not include persisted-index maintenance. Therefore they reject opening a box that already contains persisted index definitions.

This avoids the unsafe state:

```text
full creates index
-> reduced profile opens box
-> reduced profile mutates primary data without index maintenance
-> full reopens stale index
```

The safe contract is explicit rejection rather than silent index corruption.

## Binary-size policy

PR #13 same-commit native-size reproducibility remains intact. Query/index work must not invent a cross-commit binary-size threshold. That remains a separate hardening policy.

## Next planner sequence

Completed:

1. Dart query/index AST and validation.
2. Stable native transport representation.
3. One-call native scan executor.
4. Persisted scalar index metadata and entries.
5. Transactional index maintenance.
6. Index lifecycle create/backfill/list/drop.
7. Conservative equality planner.
8. Scan/index equivalence for the first eligible planner path.
9. Reduced-profile persisted-index safety guard.

Next:

10. Add planner diagnostics/selection tests if needed without changing public API prematurely.
11. Consider multiple-index candidate intersection for `AND` groups after measuring value.
12. Add safe range/index execution only with exact ordering and equivalence coverage.
13. Improve index lookup from table-prefix filtering to an efficient redb range strategy where semantics remain identical.
14. Consider one-redb-read-transaction native scan execution as a separate architecture/performance improvement.
15. Add query/index benchmarks only after each semantic path is proven equivalent.

## Correctness rules

- Query results come from committed native truth, not stale Dart metadata.
- Primary `data` is authoritative; indexes are derived state.
- The planner may narrow candidates but may not skip complete predicate re-evaluation.
- Scan and indexed execution must return equivalent logical results.
- Pagination is applied after deterministic record-key ordering unless a future explicit sort contract supersedes it.
- Index creation/backfill failure must not corrupt primary data.
- Reduced profiles must reject unsafe persisted-index boxes rather than silently changing behavior.
- Encrypted indexed fields must never leak through plaintext persisted index keys.
- No Dart whole-box value cache is introduced merely to improve benchmark numbers.

## Out of scope for this slice

- range/index planner eligibility;
- OR-index union planning;
- composite or unique indexes;
- full-text search;
- encrypted persisted-index representation;
- explicit `sortBy` contract;
- cross-commit binary-size policy;
- Dart 3.13 recorded-use/native tree shaking;
- Hive-file migration implementation.
