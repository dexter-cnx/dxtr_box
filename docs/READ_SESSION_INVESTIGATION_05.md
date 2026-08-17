# dxtr_box 0.5 Read-session Investigation

## Decision

**Reject a production reusable read-session API for 0.5.**

The investigation found no compelling performance or product case that justifies adding a long-lived redb snapshot lifecycle after PR #36. Ordinary `Box.get`, `Box.containsKey`, and `Box.getAll` keep their current authoritative fresh-per-call semantics.

This is an evidence-backed rejection, not a claim that snapshot sessions can never be useful. Revisit only if a concrete product workflow requires an explicit coherent snapshot across multiple logically separate calls.

## Scope evaluated

PR4 evaluated:

- redb transaction/snapshot lifetime;
- writer interaction;
- stale-data semantics;
- resource/lifecycle implications;
- compaction interaction;
- Flutter disposal/cancellation burden;
- multi-handle and cross-process visibility;
- incremental performance value after `Box.getAll`.

No public API, FRB binding, storage format, or native profile change is introduced.

## redb snapshot semantics

The project is pinned to redb 2.1.0.

A redb read transaction captures a database snapshot when `begin_read()` is called. Data committed after that point is not visible through that transaction. Read transactions may coexist with writes.

Therefore a reusable read session would have an explicit semantic contract:

```text
open session at T0
read key A
another handle/process commits at T1
read key B through same session
=> session still observes the T0 snapshot
```

That behavior can be useful for coherent snapshot reads, but it is intentionally stale relative to post-T0 commits. It cannot replace ordinary authoritative reads without weakening the package's established cross-handle/cross-process freshness expectations.

Upstream references:

- https://docs.rs/redb/2.1.0/redb/trait.ReadableDatabase.html
- https://docs.rs/crate/redb/2.1.0

## Resource and maintenance interaction

redb tracks live read transactions. Long-lived snapshots therefore add native lifecycle state that must be explicitly released.

More importantly for the currently pinned dependency, the redb changelog for 2.1.1 includes a fix for a panic when `compact()` is called while a read transaction is in progress. dxtr_box intentionally remains pinned to 2.1.0 during this milestone, so introducing intentionally long-lived read transactions would increase exposure to a known upstream edge case around an existing public maintenance operation.

Reference:

- https://docs.rs/crate/redb/2.1.2/source/CHANGELOG.md

This does not mean current short per-operation transactions are unsafe. It is specifically an argument against deliberately extending their lifetime across Flutter calls while remaining on redb 2.1.0.

## Performance case after PR2 and PR3

PR1 corrected medium plaintext decomposition measured approximately:

```text
transaction + table open       0.567 us
lookup + copy hit              0.191 us
MessagePack validation         0.211 us
full plaintext db_get hit      1.055 us
```

PR2 then reduced generated FRB point-read dispatch to roughly:

```text
get hit          4.312 us
contains hit     2.570 us
```

The remaining Future-based native adapter path was roughly 17-21 us in the controlled run.

A reusable native transaction could primarily avoid transaction/table-open work. The measured native setup cost is sub-microsecond and is no longer the dominant single-key cost.

For callers that already know multiple keys, PR3 provides the stronger optimization:

```text
Box.getAll(keys)
  -> one Dart/FRB crossing
  -> one redb ReadTransaction
  -> one DATA table open
  -> N reads
```

Hosted PR3 evidence:

| Keys | `Box.getAll` | N independent `Box.get` | Improvement |
|---:|---:|---:|---:|
| 10 | 445 us | 636 us | ~1.43x |
| 100 | 814 us | 5,256 us | ~6.46x |
| 1,000 | 3,729 us | 32,032 us | ~8.59x |

A session that exposes individual reads across multiple Dart calls would still pay repeated public/FRB call overhead unless it also batches work. Once it batches work, it overlaps substantially with the already-shipped `getAll` design.

## Flutter/API lifecycle cost

A safe session API would require all of the following to be specified and tested:

- explicit `close`/`dispose` semantics;
- behavior after box close;
- behavior during `compact`;
- behavior during encryption migration;
- handling of leaked sessions;
- isolate/thread ownership or a native session registry;
- invalid/stale session IDs across native teardown;
- interaction with multiple Dart handles;
- explicit documentation that session reads may be stale;
- encrypted reads retaining AEAD authentication for every value.

That is meaningful API and lifecycle surface, not a transparent micro-optimization.

## Rejected designs

### Implicit session per Box

Rejected. It would silently make ordinary reads stale and weaken existing freshness behavior.

### Hidden session with periodic refresh

Rejected. Time-based refresh creates nondeterministic visibility semantics and still requires lifecycle/resource management.

### Explicit session solely for speed

Rejected for 0.5. Existing evidence shows native transaction setup is too small to justify the added public/native lifecycle complexity, and `getAll` already amortizes setup for known multi-key workloads.

### Upgrade redb and add sessions in the same PR

Rejected. A dependency upgrade would expand scope and would not solve the product-semantics question. Dependency upgrades should be evaluated independently with storage-compatibility and regression evidence.

## Conditions for future reconsideration

Revisit an explicit read-session API only if all of these are true:

1. A concrete consumer requires one coherent snapshot across multiple logically separate operations.
2. The stale-within-session contract is desirable and can be named explicitly.
3. Benchmark evidence shows material benefit beyond `Box.getAll` for that workload.
4. redb version/lifecycle behavior is reviewed independently, including compaction interaction.
5. Session leak/close/box-close/migration semantics are specified before implementation.
6. Cross-process freshness remains unchanged outside the explicit session.
7. Encryption continues to authenticate every returned value.

## PR4 outcome

```text
production read-session API: rejected for 0.5
ordinary get freshness:       unchanged
containsKey freshness:        unchanged
getAll freshness:             unchanged per call
Dart whole-box cache:          none
storage format:               unchanged (dxtr_box/1)
FRB version:                  unchanged (2.8.0)
redb version:                 unchanged (2.1.0)
native profiles:              unchanged (minimal | encryption | full)
```

PR5 can proceed to the expanded comparison matrix and 0.5 closure audit.