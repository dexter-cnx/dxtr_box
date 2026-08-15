# Query / Index 0.3 Design Contract

## Status after PR #14

The first executable 0.3 query/index slice is implemented and validated:

- `Box.query(BoxQuery)` serializes the public Dart AST with `DxtrCodec` and performs one FRB call per query.
- Rust decodes the query once, evaluates comparisons/groups against committed native records, supports dotted nested-field lookup, and applies deterministic key ordering before pagination.
- Native scans work for plaintext and encrypted boxes. Encrypted records are decrypted only inside the trusted native storage path.
- Persisted named scalar secondary-index definitions and entries exist in redb under the `full` profile.
- Index create/backfill/drop and primary mutation maintenance are transactionally coupled to redb writes.
- Encrypted boxes intentionally reject persisted index creation until a non-leaking encrypted-index representation is designed; native scan queries remain available.
- Plaintext -> encrypted migration is rejected while persisted index definitions exist, preventing a security-mode transition that would leave plaintext-derived index state behind.
- The query planner does **not** consume persisted indexes yet. Native scan remains the authoritative execution path, so scan/index equivalence is the next milestone rather than an implicit assumption.

PR #14 final head was validated by the normal CI and Platform Builds workflows across the existing supported toolchains and native profile matrix.

## Scope

0.3 introduces structured query and secondary-index capabilities without weakening the existing storage, encryption, durability, lifecycle, or Cargo profile contracts.

The milestone is intentionally split into layers so the public Dart query model does not depend on a particular index implementation.

## Profile contract remains unchanged

The established native profiles remain exactly three public product profiles:

```text
minimal     = CRUD + lifecycle + native watch
encryption  = minimal + encrypted create/open/read/write
full        = encryption + maintenance + query/index implementation
```

`full` may include internal optional dependencies needed by query/index execution (currently `rmpv`) without introducing a fourth public profile.

Do not add a fourth public build profile just for query/index work.

During 0.3, query/index implementation must preserve these three named profiles and their ordering. Reduced builds retain the stable FRB symbol surface and fail explicitly when a query/index operation requires `full`.

## Binary-size regression policy is separate

The PR #13 same-commit size-stability gate remains intact.

0.3 query/index work must **not** introduce or tune a cross-commit binary-size regression threshold. Any future cross-commit size budget is a separate policy change with controlled baseline selection, toolchain/platform metadata, and documented exceptions.

Query/index PRs may record measured size impact for information, but correctness and API work must not be blocked on defining that future policy.

## Public naming policy

`Dxtr` is reserved for the product/root namespace such as `DxtrBox`. Feature-level public types use domain names instead of repeating the brand prefix.

The query surface therefore uses:

```text
BoxQuery
QueryFilter
QueryComparison
QueryGroup
QueryOperator
QueryLogicalOperator
IndexDefinition
```

This keeps call sites readable while retaining enough domain context to avoid overly generic names such as bare `Query`, `And`, or `Or`.

## Dart query model

The public declarative AST is:

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

Initial comparison operators:

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

Fields use dotted paths such as:

```text
status
profile.age
address.country
```

The Dart AST is execution-agnostic. It is serialized across FRB and currently evaluated by the native scan executor. The planner can consume persisted indexes later without changing normal query construction.

## Initial index contract

0.3 starts with named scalar secondary indexes:

```dart
IndexDefinition(
  name: 'by-status',
  field: 'status',
)
```

Current constraints:

- one indexed dotted field path per index;
- scalar index keys only;
- no implicit full-text semantics;
- no composite indexes yet;
- no multi-value/list expansion yet;
- no uniqueness guarantee;
- index names are explicit and stable;
- persisted index creation is currently plaintext-only.

Composite, text, unique, list/multi-value, collation-aware, and encrypted persisted-index representations are follow-up capabilities and must not be smuggled into the first storage format.

## Storage architecture

The existing primary record table remains authoritative:

```text
data: record key -> MessagePack payload or encrypted payload
```

Secondary indexes are derived state. They never become the only copy of user data.

The persisted-index layout is:

```text
data
meta
index_definitions   # name -> dotted field path
index_entries       # encoded composite index entry -> record key payload
```

Index entry keys use an encoded binary composite representation rather than delimiter concatenation.

Index mutation is transactionally coupled to primary-record mutation. A committed `put`, `putAll`, `delete`, `deleteAll`, or `clear` cannot leave an index representing a different committed database state.

Index creation validates the definition, backfills current primary data, persists the definition, and commits derived entries atomically. Dropping an index removes its definition and derived entries.

## Encryption semantics

For encrypted boxes:

- primary payloads remain authenticated ciphertext at rest;
- native scan code may inspect decrypted MessagePack only inside the trusted storage path;
- persisted secondary index keys must not silently leak plaintext indexed values.

Therefore encrypted boxes currently reject persisted index creation. This is intentional, not an implementation gap to bypass. Native scan queries remain supported for encrypted boxes.

A plaintext box with persisted index definitions also cannot be migrated to encrypted storage until an encrypted-index representation and migration semantics are designed.

## Query execution

Current execution path:

```text
Box.query(BoxQuery)
  -> validate/serialize AST with DxtrCodec
  -> NativeQueryApi.scanQuery
  -> one FRB call
  -> Rust decode query once
  -> enumerate committed native records
  -> decrypt when box is encrypted
  -> decode MessagePack value
  -> evaluate comparison/group predicate
  -> deterministic record-key ordering
  -> apply offset/limit
  -> return matching key + payload records in one FRB response
  -> Dart decode payloads
```

This satisfies the one-FRB-call-per-query requirement. The current scan implementation is not yet a single-redb-read-transaction executor; improving internal scan transaction shape is a performance/architecture follow-up and must preserve semantics.

## Planner sequence

Completed:

1. Dart query/index AST and validation.
2. Stable native transport representation for the AST.
3. Native scan query returning matching record keys and payloads in one FRB boundary crossing.
4. Query semantics coverage for plaintext and encrypted boxes.
5. Persisted index definition metadata.
6. Transactional index maintenance for put/putAll/delete/deleteAll/clear.
7. Index create/backfill/list/drop lifecycle.

Next:

8. Query planner choosing an eligible persisted index vs native scan while preserving identical logical results and deterministic ordering.
9. Add explicit scan/index equivalence tests for every planner-eligible operator.
10. Explain/diagnostic metadata only after planner behavior is stable.

## Correctness rules

- Query results are based on native committed truth, not stale Dart key metadata.
- No Dart whole-box value cache is introduced to make queries appear fast.
- Scan and indexed execution must return equivalent logical results once the planner is enabled.
- Pagination is applied deterministically after predicate evaluation according to documented record-key ordering unless a future explicit sort contract supersedes it.
- Index creation/backfill failure must not corrupt primary data.
- Opening an older box without index metadata continues to work.
- Index format changes require explicit persisted-version handling.
- Reduced profiles must fail explicitly for unavailable query/index operations rather than silently changing behavior.

## Testing gates

Current PR #14 coverage includes:

```text
Dart
  AST validation
  nested field paths
  boolean groups
  pagination validation
  Box.query facade behavior
  index facade capability behavior

Rust/native scan
  comparison/group evaluation
  nested map lookup
  encrypted scan support
  one native call per query
  deterministic record ordering before pagination

Persisted indexes
  create/backfill/list/drop
  mutation maintenance
  reopen definition persistence
  encrypted-index rejection
  migration guard when persisted indexes exist

Profiles
  minimal green
  encryption green
  full green
```

Before planner/index execution is considered complete, add comprehensive scan/index result-equivalence and planner-selection tests across supported operators and nested fields.

## Out of scope for this slice

- query planner/index-backed execution;
- cross-commit binary-size regression policy;
- Dart 3.13 recorded-use/native tree shaking;
- full-text search;
- composite or unique indexes;
- encrypted persisted-index representation;
- schema migration/custom-object work;
- Hive-file migration implementation.

Those can proceed in separate changes without changing this query/index foundation.
