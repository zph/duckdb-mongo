# Low-Level Design: Read Preference

## Problem Statement

The extension currently uses the default read preference (`primary`) for all reads. Users connecting to replica sets or sharded clusters have no per-query control over which members serve reads. Heavy analytics queries should be routable to secondaries to avoid impacting the primary.

The connection string supports `?readPreference=secondaryPreferred`, but that's static — it applies to all queries on that connection. Per-query control requires a parameter or session setting.

## Goal

Allow users to set MongoDB read preference per-query (via `mongo_scan` parameter) or per-session (via `SET`), following the same layered pattern as `afterClusterTime`.

## Approach: Layered (Parameter + SET)

### Mechanism 1: Named parameter on `mongo_scan`

```sql
SELECT * FROM mongo_scan('mongodb://...', 'mydb', 'analytics',
    read_preference := 'secondaryPreferred'
);
```

### Mechanism 2: Session-level SET

```sql
SET mongo_read_preference = 'secondaryPreferred';
SELECT * FROM mongo_test.large_collection;  -- reads from secondary
RESET mongo_read_preference;
```

### Accepted Values

| Value | Behavior |
|-------|----------|
| `primary` | Default. Reads from primary only |
| `primaryPreferred` | Reads from primary; falls back to secondary if primary unavailable |
| `secondary` | Reads from secondary only |
| `secondaryPreferred` | Reads from secondary; falls back to primary if no secondary available |
| `nearest` | Reads from the member with lowest network latency |

Case-insensitive. Invalid values raise `InvalidInputException`.

### Precedence

```
1. read_preference := <value>   on mongo_scan  (highest priority)
2. SET mongo_read_preference     (session fallback)
3. Connection string ?readPreference=  (connection-level)
4. 'primary'                     (MongoDB default)
```

Per-query parameter overrides session setting, which overrides connection string.

## Implementation

### mongocxx API

```cpp
mongocxx::read_preference rp;
rp.mode(mongocxx::read_preference::read_mode::k_secondary_preferred);

// Apply to find
mongocxx::options::find opts;
opts.read_preference(rp);
collection.find(filter, opts);

// Apply to aggregate
mongocxx::options::aggregate agg_opts;
agg_opts.read_preference(rp);
collection.aggregate(pipeline, agg_opts);
```

### Parsing Utility

```cpp
// In mongo_compat.hpp
mongocxx::read_preference::read_mode ParseReadPreference(const string &input);
```

Maps case-insensitive string to `mongocxx::read_preference::read_mode` enum:
- `"primary"` → `k_primary`
- `"primaryPreferred"` / `"primary_preferred"` → `k_primary_preferred`
- `"secondary"` → `k_secondary`
- `"secondaryPreferred"` / `"secondary_preferred"` → `k_secondary_preferred`
- `"nearest"` → `k_nearest`

Accept both camelCase (MongoDB convention) and snake_case.

### Key Files to Modify

| File | Change |
|------|--------|
| `src/include/mongo_compat.hpp` | `ParseReadPreference()` utility |
| `src/mongo_extension.cpp` | Register `mongo_read_preference` setting + `read_preference` named parameter |
| `src/include/mongo_table_function.hpp` | Add `read_preference` field to `MongoScanData` |
| `src/mongo_table_function.cpp` | Parse in bind, resolve in init, apply to `find_options` and `aggregate_options` |

### Interaction with afterClusterTime

Read preference and afterClusterTime are orthogonal — they compose naturally. A query can use both:

```sql
SELECT * FROM mongo_scan('mongodb://...', 'mydb', 'orders',
    read_preference := 'secondaryPreferred',
    after_cluster_time := '1779206684:15'
);
```

This reads from a secondary, but only after the secondary has replicated past the given timestamp.

### Edge Cases

- **Standalone MongoDB**: Read preference is ignored (only one server)
- **Empty / NULL**: Treated as "use default" (whatever the connection string specifies, or `primary`)
- **`secondary` on a standalone or single-node replica set**: MongoDB returns an error; this should propagate as a query error, not be silently swallowed
- **Legacy driver (3.x)**: `mongocxx::read_preference` API is identical in 3.x and 4.x
