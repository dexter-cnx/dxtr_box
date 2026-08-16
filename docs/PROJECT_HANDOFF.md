# dxtr_box Project Handoff

## Product

**dxtr_box — The Hive replacement, forged in Rust. By Dxtr.**

Target: Hive-simple Flutter ergonomics backed by redb, with durable storage outside the Dart heap and no application-level model code generation.

The 1.0 claim is functional replacement for practical Hive/Hive CE local-database workloads, not source-level API compatibility. `docs/HIVE_FUNCTIONAL_PARITY.md` remains a release gate.

## Current snapshot — 0.3 single-snapshot query execution

Main contains the native query/index foundation, equality/range planning, nested indexes, AND intersection, and bounded index-name redb iteration. Current branch:

```text
feature/0.3-query-read-transaction
```

refactors native query execution so planner lookup, fallback key enumeration, and primary reads share one redb `ReadTransaction`, without changing the public Dart API or FRB shape.

Current capabilities include:

- `DxtrBox`, `Box`, `BoxEvent` Flutter facade.
- Dart >= 3.4.0 / Flutter >= 3.22.0.
- MessagePack dynamic codec.
- Rust `redb = 2.1.0`, one `{box}.dxtr` file per box.
- Transactional CRUD/bulk CRUD/lifecycle.
- Explicit compact and plaintext-to-encrypted migration.
- Native cross-handle watch fan-out through FRB streams.
- Argon2 + ChaCha20Poly1305 persisted encryption.
- Process crash/reopen durability coverage.
- Exactly three public native profiles: `minimal`, `encryption`, `full`.
- Checked-in FRB 2.8 bindings with drift CI.
- Android/iOS/macOS/Linux/Windows example build coverage.
- Hive CE benchmark smoke harness.
- Declarative `Box.query(BoxQuery)` with one FRB call per query.
- Persisted named scalar indexes under `full`.
- Planner-backed equality and ordered range candidate narrowing.
- Multi-index candidate intersection for AND groups.

## Query/index public model

```text
BoxQuery
QueryFilter
QueryComparison
QueryGroup.and(...)
QueryGroup.or(...)
QueryOperator
QueryLogicalOperator
IndexDefinition
```

Supported predicate semantics:

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
AND / OR groups
dotted nested field lookup
```

Numeric comparison preserves MessagePack integer precision across signed/unsigned domains.

## Persisted index state

```text
index_definitions
index_entries
```

Index lifecycle supports create/backfill/list/drop. Primary mutation and derived index maintenance share the same redb write transaction.

Entry key layout:

```text
[index-name length][index-name]
[scalar length][MessagePack scalar]
[record-key length][record-key]
```

Primary `data` remains authoritative; indexes are derived state.

## Current planner contract

Planner-eligible candidate narrowing now includes:

```text
equal
greaterThan
greaterThanOrEqual
lessThan
lessThanOrEqual
between
```

Eligibility applies at the top level or recursively under `AND` groups when a persisted index exists for the exact dotted field path.

Range bounds are currently limited to ordered numeric/string scalar values.

The planner does **not** descend into `OR` groups for narrowing. `notEqual`, `isNull`, and `isNotNull` remain scan-backed.

Nested fields such as `profile.age` can be indexed and planned.

## Multiple-index AND intersection

For an AND query, every usable indexed predicate produces a record-key candidate set. Candidate sets are sorted by cardinality and intersected from the smallest set first.

Example:

```text
status == active       -> by-status set
profile.age >= 18      -> by-age set
intersection           -> candidate keys
primary record recheck -> final truth
```

Missing indexes do not fail a query. Any remaining indexed predicates may still narrow candidates; all predicates are re-evaluated from primary committed data.

## Range lookup correctness constraint

Persisted scalar components are ordinary MessagePack bytes. Their lexicographic byte order is not a general numeric order.

Therefore current range planning does **not** assume raw MessagePack bytes can be used directly as redb numeric range bounds.

Current correctness-first path:

```text
matching index definition
  -> inspect entries for that index
  -> decode scalar component
  -> compare with query engine's exact comparator
  -> collect matching record keys
```

A future efficient redb range seek requires an order-preserving scalar encoding or equivalent proven ordering contract.

## Query execution path

```text
Box.query(BoxQuery)
  -> DxtrCodec query serialization
  -> NativeQueryApi.scanQuery
  -> one FRB call
  -> query::decode_query once
  -> open one redb ReadTransaction snapshot
  -> index::candidate_keys(read, filter)
       -> definitions + equality/range candidate sets from the same snapshot
       -> optional AND intersection
       -> None when scan is required
  -> fallback key enumeration from the same snapshot when needed
  -> sort + deduplicate candidate keys
  -> read primary records from the same snapshot
  -> decrypt if required
  -> evaluate complete original predicate
  -> deterministic key ordering
  -> offset / limit
  -> one FRB response
```

The persisted index only narrows candidates. Full predicate evaluation against committed primary data remains mandatory.

## Scan/index equivalence gate

`rust/tests/query_index.rs` now covers:

- equality planner equivalence;
- nested `profile.age` range equivalence for `>`, `>=`, `<`, `<=`;
- inclusive `between` equivalence;
- multi-index AND intersection equivalence;
- indexed-field mutation correctness;
- index definitions surviving reopen;
- encrypted boxes using scan and rejecting persisted index creation.

Every future planner rule must add matching scan-vs-index equivalence coverage first.

## Public native profile contract

Keep exactly these three public profiles:

```text
minimal
  CRUD + lifecycle + native watch

encryption
  minimal + encrypted create/open/read/write

full
  encryption + maintenance + query/index implementation
```

Do not add a fourth public query profile.

Reduced profiles reject opening boxes containing persisted index definitions because they cannot safely maintain derived index state.

## Encryption/index security policy

Encrypted boxes may use native scan query.

Encrypted boxes may not create persisted secondary indexes yet because plaintext-derived scalar keys would leak protected values.

Plaintext-to-encrypted migration is rejected while persisted index definitions exist.

## Mutation atomicity invariant

```text
put / putAll / delete / deleteAll / clear
  -> compute index changes
  -> mutate DATA + index_entries
  -> same redb write transaction
  -> one commit
  -> emit watch events after commit only
```

Index creation backfills and persists definition + entries atomically.

## Minimum SDK and native build policy

```text
Dart >= 3.4.0 < 4.0.0
Flutter >= 3.22.0
```

FRB and Cargokit native naming must remain:

```text
rust_lib_dxtr_box
```

`rust_builder/` remains the native build owner. Dart 3.13 recorded-use/native tree shaking stays deferred.

## Benchmark and size policy

Benchmark timings on shared runners are informational. Do not weaken durability or add a Dart whole-box cache for benchmark numbers.

PR #12/#13 established three-profile native-size measurement and same-commit reproducibility. Cross-commit size thresholds remain a separate hardening task.

## Developer workflow

Preferred root targets:

```text
make preflight
make frb-generate
make native-test
make query-index-test
make process-crash
make benchmark-smoke
make benchmark-full
make rust-check
make native-build-minimal
make native-build-encryption
make native-size-baseline
make native-size-stability
make example-android
make example-linux
make example-windows
make example-macos
make example-ios
```

## Current validation expectation

Every query/index PR should preserve:

```text
Minimum SDK / Ubuntu
Current Flutter analyze + tests
FRB generated-binding drift gate
Rust Ubuntu + macOS + Windows
  rustfmt
  clippy -D warnings
  minimal tests
  encryption tests
  full tests
Native Linux FRB round trip + benchmark smoke
Native-size same-commit reproducibility
Platform Builds: Android/iOS/macOS/Linux/Windows
```

The current range planner was additionally finalized through a temporary workflow that ran rustfmt, clippy, and all three profile test suites before committing the final code and removing its temporary tooling.

## Next 0.3 sequence

1. Completed: bounded persisted-index lookup/drop cleanup by index-name range.
2. Completed: one-redb-read-transaction query execution for planner/fallback/primary reads.
3. Add planner diagnostics/selection tests only if useful for maintainability.
4. Define an explicit public `sortBy` contract separately.
5. Add query/index benchmark scenarios now that core execution semantics are stable.
6. Continue point-get/contains performance diagnosis independently.
7. Keep encrypted-index design, cross-commit size policy, and Dart 3.13 tree shaking separate.

## Later roadmap

### 0.3.x

- planner/index execution hardening
- explicit sort contract
- query/index benchmark scenarios
- Hive CE migration design/implementation

### 0.4.x

- production/package hardening
- controlled cross-commit native-size policy
- broader Flutter local-database comparison

### 0.9.x

Refresh Hive Functional Parity Audit against the then-current Hive CE release and close every practical `Gap`.

### 1.0.0

- no practical parity gaps
- stable storage/API contract
- Web/IndexedDB strategy complete
- pub.dev release readiness

## Non-negotiable rules

- Never silently weaken storage durability for benchmark speed.
- Never introduce a Dart whole-box cache without a coherency contract.
- Never leak encrypted indexed fields through plaintext persisted index keys.
- Never add another public native profile casually.
- Never raise the minimum Flutter/Dart floor incidentally.
- Never merge native API changes with stale FRB generated bindings.
- Never use an index as final truth; primary committed data remains authoritative.
- Never assume raw MessagePack numeric byte order equals query numeric order.
- Keep README, this handoff, `CODE_WALKTHROUGH.md`, and `QUERY_INDEX_03.md` aligned with actual implementation state.

## Latest 0.3 optimization — bounded index-name iteration

`feature/0.3-index-prefix-range` replaces whole-`index_entries` iteration for candidate lookup and index-drop cleanup with redb ranges bounded to one encoded index-name prefix. Public Dart/FRB APIs and planner eligibility do not change.

Important constraint: this is **not** scalar-order range seeking. MessagePack scalar components are still decoded and compared using the query engine comparator. Any future scalar-level seek requires an order-preserving encoding proven equivalent to query numeric/string semantics.

The next architecture work is no longer read-transaction plumbing: one native query now observes one redb read snapshot across planner, fallback, and primary reads. Next candidates are planner diagnostics, an explicit sort contract, and benchmark scenarios; scalar-level redb seeks still require a separately proven order-preserving scalar encoding.

