# Query sort contract 0.3

This document defines the public sort semantics for `Box.query(...)` before implementation changes are merged.

## Public model

```dart
BoxQuery(
  where: ...,
  sortBy: [
    QuerySort(
      field: 'profile.age',
      direction: QuerySortDirection.ascending,
      nulls: QueryNullOrder.last,
    ),
  ],
)
```

`sortBy` is an ordered list of sort clauses. Clauses are applied lexicographically in declaration order. Record key ascending is the final deterministic tie-breaker.

## Supported values

Ordered non-null values are numbers and strings, matching the existing ordered query comparator. Numeric ordering preserves signed/unsigned integer precision and mixed integer/float boundary handling.

A sort field containing any other non-null value type is rejected rather than assigned an implicit cross-type order.

## Missing and null fields

Missing fields and explicit `null` are one nullish category for sorting. `QueryNullOrder.first` and `QueryNullOrder.last` control placement independently of ascending/descending direction.

## Pagination

Filtering and full predicate recheck happen first. Sorting happens over all matching records in the same redb read snapshot. `offset` and `limit` are applied only after the complete ordered result is known.

Without `sortBy`, existing deterministic record-key ascending order remains unchanged and may retain early pagination behavior.

## Index interaction

Persisted indexes remain candidate narrowing only. This contract does not claim index-backed ordering, scalar byte-order seeking, or sort elimination. Primary committed records remain authoritative.

## Stability and errors

- dotted nested field paths are supported;
- duplicate sort fields are allowed and evaluated in declaration order, though later duplicates are redundant;
- empty `sortBy` is equivalent to no explicit sort;
- incompatible non-null ordered types fail the query explicitly;
- NaN is rejected as non-orderable;
- final record-key ascending tie-break makes results deterministic.

## Non-goals

This slice does not add locale collation, case-insensitive collation, custom comparators, list sorting, DateTime-specific ordering, index-backed ordering, or composite persisted indexes.
