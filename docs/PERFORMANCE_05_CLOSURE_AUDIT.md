# dxtr_box 0.5 Closure Audit

## Scope

This is the final audit for the 0.5 Performance / Read-path Optimization milestone. It closes the milestone only if the final PR passes the repository's full merge quality bar. It does not introduce another optimization.

## Final 0.5 sequence

```text
PR 1 / #33 — read-path decomposition + corrected baseline      complete
PR 2 / #35 — single-key FRB boundary optimization              complete / merged
PR 3 / #36 — one-snapshot batch/multi-key read path            complete / merged
PR 4 / #37 — read-session investigation                        complete / merged
PR 5       — comparison matrix + closure audit                 this PR
```

## Production changes accepted in 0.5

### Single-key reads

Only Rust `get` and `contains_key` use `#[frb(sync)]`. Public Dart APIs remain `Future` based. Query, batch, mutation, migration, scan, and other heavier paths remain asynchronous.

Controlled boundary evidence from PR #35:

```text
generated FRB get        ~226 us -> 4.312 us   ~52x faster
generated FRB contains   ~197 us -> 2.570 us   ~77x faster
```

### Multi-key reads

PR #36 added:

```dart
Future<List<MapEntry<String, dynamic>>> Box.getAll(
  Iterable<String> keys,
)
```

The implementation uses one asynchronous FRB call, one redb read transaction, and one DATA table open for the requested key set. Hits preserve input order, misses are omitted, duplicate input keys produce duplicate result entries, empty input does not cross native, and encrypted hits retain full AEAD authentication.

Hosted diagnostic evidence from the PR3 batch benchmark:

| Keys | `Box.getAll` | N independent `Box.get` | Relative improvement |
|---:|---:|---:|---:|
| 10 | 445 us | 636 us | ~1.43x |
| 100 | 814 us | 5,256 us | ~6.46x |
| 1,000 | 3,729 us | 32,032 us | ~8.59x |

These are diagnostic hosted-runner timings, not product guarantees.

## Read-session decision

PR #37 rejected a reusable long-lived read-session API for 0.5. A redb read transaction is a fixed snapshot, so cross-call reuse necessarily introduces stale-data semantics. The measured transaction + table-open cost was already small relative to the runtime boundary, and `getAll` addresses the main known multi-key use case without cross-call lifecycle and freshness complexity.

Ordinary `get`, `containsKey`, `getAll`, and query behavior therefore continue to create fresh authoritative snapshots per operation/call rather than sharing an implicit stale snapshot.

## Comparison evidence policy

The four-engine comparison matrix remains intentionally limited to contracts shared across dxtr_box, Hive CE, Sembast, and SQLite:

```text
sequential_put
batch_put
point_get
contains
delete_all
reopen_read
```

It is not extended with a synthetic `getAll` comparison because the other adapters do not expose an equivalent product contract with identical semantics. The dedicated dxtr_box batch benchmark is the appropriate evidence for the new API. This avoids presenting an apples-to-oranges comparison as a product claim.

PR5 must rerun:

```text
benchmark comparison correctness
comparison diagnostic timing
benchmark smoke
full Dart tests
native integration
Rust minimal/encryption/full checks
query/index/migration regressions
FRB generated-binding drift
native-size policy
package/pub dry-run
Android/iOS/macOS/Linux/Windows staged consumers
minimum Flutter 3.22.0 / Dart 3.4.0
```

The repository's `Merge Gate / full quality bar` is the final acceptance gate.

## 0.5 acceptance criteria

| Criterion | Closure state |
|---|---|
| Evidence-backed bottleneck decomposition | satisfied by PR #33 |
| At least one production read-path optimization | satisfied by PR #35 |
| `get` / `containsKey` improvement | satisfied by PR #35 evidence |
| Efficient multi-key support or evidence-based rejection | satisfied by PR #36 |
| No Dart whole-box cache | preserved |
| Cross-handle/cross-process authoritative reads | preserved |
| Full encrypted authentication | preserved |
| `dxtr_box/1` remains readable | preserved |
| Exactly `minimal | encryption | full` profiles | preserved |
| Dart >=3.4 / Flutter >=3.22 | preserved |
| FRB exactly 2.8.0 | preserved |
| Query/index/migration correctness | required by final Merge Gate |
| Native-size regression policy | required by final Merge Gate |
| Five staged platform consumers | required by final Merge Gate |
| Read-session decision | satisfied by PR #37 |
| Final comparison/closure audit | satisfied when this PR Merge Gate passes |

## Milestone decision

If this PR's full Merge Gate passes, 0.5 is complete. Further performance work should start as a new milestone with a new measured bottleneck rather than extending 0.5 opportunistically.
