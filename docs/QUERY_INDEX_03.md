# Query / Index 0.3 Design Contract

## Scope

0.3 introduces structured query and secondary-index capabilities without weakening the existing storage, encryption, durability, lifecycle, or Cargo profile contracts.

The milestone is intentionally split into layers so the public Dart query model does not depend on a particular index implementation.

## Profile contract remains unchanged

The established native profiles remain:

```text
minimal     = CRUD + lifecycle + native watch
encryption  = minimal + encrypted create/open/read/write
full        = encryption + maintenance (compact + plaintext migration)
```

Do not add a fourth public build profile just for query/index work.

During 0.3, query/index implementation must be introduced in a way that preserves these three named profiles and their ordering. If native index machinery has meaningful binary-size cost, it may initially be compiled only into `full`, while the Dart contract remains stable and reduced profiles fail explicitly for unavailable native query/index operations. A later decision may move mature low-cost query primitives into the core profile, but that requires an explicit profile-contract review rather than an incidental Cargo edit.

## Binary-size regression policy is separate

The PR #13 same-commit size-stability gate remains intact.

0.3 query/index work must **not** introduce or tune a cross-commit binary-size regression threshold. Any future cross-commit size budget is a separate policy change with controlled baseline selection, toolchain/platform metadata, and documented exceptions.

Query/index PRs may record their measured size impact for information, but correctness and API work must not be blocked on defining that future policy.

## Dart query model

The first foundation exposes a declarative AST:

```text
DxtrQuery
  where: DxtrCondition
  limit: int?
  offset: int

DxtrCondition
  DxtrCompare
  DxtrAnd
  DxtrOr
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

The Dart AST is intentionally execution-agnostic. It can be serialized across FRB and evaluated by a native scan before secondary indexes exist, then planned against indexes later without changing normal call-site query construction.

## Initial index contract

0.3 starts with named scalar secondary indexes:

```text
DxtrIndexDefinition(
  name: 'by-status',
  field: 'status',
)
```

Initial constraints:

- one indexed dotted field path per index;
- scalar index keys only;
- no implicit full-text semantics;
- no composite indexes yet;
- no multi-value/list expansion yet;
- no uniqueness guarantee in the first implementation;
- index names are explicit and stable.

Composite, text, unique, list/multi-value, and collation-aware indexes are follow-up capabilities and must not be smuggled into the first storage format.

## Storage architecture

The existing primary record table remains authoritative:

```text
data: record key -> MessagePack payload or encrypted payload
```

Secondary indexes are derived state. They must never become the only copy of user data.

The target full-profile layout is conceptually:

```text
data
meta
index_definitions
index_entries
```

Index mutation must be transactionally coupled to primary-record mutation. A committed `put`, `putAll`, `delete`, `deleteAll`, or `clear` must not leave an index representing a different committed database state.

## Encryption semantics

For encrypted boxes:

- primary payloads remain authenticated ciphertext at rest;
- query/index code may inspect decrypted MessagePack only inside the native trusted storage path;
- persisted secondary index keys must not silently leak plaintext indexed values.

Therefore the first persisted-index implementation must explicitly choose and document an encrypted-index representation before encrypted-box indexes are enabled. Until that representation is implemented, encrypted query execution may use a native scan and encrypted boxes must reject persisted index creation rather than leaking fields.

## Query execution sequence

Implementation sequence:

1. Dart query/index AST and validation.
2. FRB transport types for the AST.
3. Native full-profile scan query returning matching record keys and payloads in one boundary crossing.
4. Query semantics tests against plaintext and encrypted boxes.
5. Persisted index definition metadata.
6. Transactional index maintenance for put/putAll/delete/deleteAll/clear.
7. Index backfill/create/drop operations with deterministic busy/lifecycle behavior.
8. Query planner choosing eligible index vs native scan while preserving identical results.
9. Explain/diagnostic metadata only after planner behavior is stable.

## Correctness rules

- Query results are based on native committed truth, not stale Dart key metadata.
- No Dart whole-box value cache is introduced to make queries appear fast.
- Scan and indexed execution must return equivalent logical results.
- Pagination is applied deterministically after predicate evaluation according to the defined result ordering.
- Result ordering must be documented before indexed execution is exposed publicly. Do not rely on accidental redb iteration order as an API guarantee.
- Index creation/backfill failure must not corrupt primary data.
- Opening an older box without index metadata must continue to work.
- Index format changes require explicit persisted-version handling.

## Testing gates

Before 0.3 query/index is considered complete:

```text
Dart
  AST validation
  nested field paths
  boolean groups
  pagination validation

Rust/native scan
  all comparison operators
  nested map lookup
  missing field vs null semantics
  encrypted scan parity
  one native call per query, not one FFI call per record

Persisted indexes
  create/backfill/drop
  put/putAll maintenance
  delete/deleteAll/clear maintenance
  reopen persistence
  scan/index result equivalence
  failure safety
  unsupported encrypted-index behavior until secure representation exists

Profiles
  minimal remains green
  encryption remains green
  full remains green
```

## Out of scope for this slice

- cross-commit binary-size regression policy;
- Dart 3.13 recorded-use/native tree shaking;
- full-text search;
- composite or unique indexes;
- schema migration/custom-object work;
- Hive-file migration implementation.

Those can proceed in separate changes without changing this query/index foundation.
