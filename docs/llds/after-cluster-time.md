# Low-Level Design: afterClusterTime / Causal Consistency Reads

## Problem Statement

After querying MongoDB via `mongo_scan`, users capture the `operationTime` via `mongo_operation_time()`. There's currently no way to pass that timestamp back into a subsequent read to get causal consistency — i.e., to guarantee the next read sees at least the effects of the prior operation.

MongoDB supports this via `readConcern: { afterClusterTime: <BsonTimestamp> }`, but the extension has no mechanism to set it.

## Goal

Allow users to pass an `afterClusterTime` value to `mongo_scan` so MongoDB blocks the read until the cluster has advanced past that timestamp. This provides **causal consistency** (read-your-writes), not time travel.

## Approach: Layered (Parameter + SET)

Both mechanisms serve different use cases and are not mutually exclusive.

### Mechanism 1: Named parameter on `mongo_scan` (explicit, per-call)

```sql
-- Capture timestamp from first read
SELECT * FROM mongo_scan('mongodb://...', 'mydb', 'orders');

-- Use it for causal consistency on second read
SELECT * FROM mongo_scan('mongodb://...', 'mydb', 'inventory',
    after_cluster_time := (SELECT mongo_operation_time())
);
```

- Follows existing pattern (`filter :=`, `pipeline :=`, `sample_size :=`)
- Explicit — visible in the SQL
- Per-call control — different scans can use different timestamps

### Mechanism 2: Session-level SET (implicit, ATTACH-friendly)

```sql
-- After a write or read, set session-wide causal consistency point
SET mongo_after_cluster_time = 7641659143652114433;

-- All subsequent mongo_scan / ATTACH queries use this timestamp
SELECT * FROM mongo_test.users;
SELECT * FROM mongo_test.orders;

-- Clear it
RESET mongo_after_cluster_time;
```

- Works with ATTACH (where `mongo_scan` parameters aren't accessible)
- Set-and-forget for session-wide consistency
- Registered via `DBConfig::AddExtensionOption()`

### Accepted Input Formats

Both the named parameter and SET accept either format:

| Format | Example | Description |
|--------|---------|-------------|
| UBIGINT | `7641659143652114433` | Raw BSON timestamp (from `mongo_operation_time()`) |
| VARCHAR | `'1779206684:15'` | MongoDB `seconds:increment` string (from oplog `ts` field) |

The extension parses the string format by splitting on `:` and reconstructing the UBIGINT: `(seconds << 32) | increment`.

### Precedence (last write wins)

Both settings write to the same internal slot. The most recent SET or parameter wins:

```
1. after_cluster_time := <value>  on mongo_scan  (highest priority, per-call)
2. SET mongo_after_cluster_time = <value>         (session fallback)
3. No afterClusterTime sent                       (default)
```

## MongoDB Wire Protocol

When `afterClusterTime` is active, the extension adds it to the `readConcern` on `find()` and `aggregate()` commands:

```json
{
  "readConcern": {
    "afterClusterTime": { "$timestamp": { "t": <seconds>, "i": <increment> } }
  }
}
```

The UBIGINT from `mongo_operation_time()` is split back into the two 32-bit components:
- `t = value >> 32`
- `i = value & 0xFFFFFFFF`

The mongocxx driver supports setting read concern on `find_options` and `aggregate_options`.

## Important: This is NOT Time Travel

`afterClusterTime` does **not** read data "as of" a past point in time. It does the opposite — it tells MongoDB "wait until you've advanced past this timestamp, then give me current data." Specifically:

- It guarantees **causal consistency**: the read sees at least the effects of all operations up to the given timestamp
- It may **block** if the target node hasn't replicated to that point yet
- The data returned is the **current** state, not a historical snapshot
- On a standalone server (no replication), `afterClusterTime` has no effect

For actual time travel / historical reads, MongoDB requires a separate feature (change streams + event sourcing, or oplog replay).

## Key Files to Modify

| File | Change |
|------|--------|
| `src/mongo_extension.cpp` | Register `mongo_after_cluster_time` extension option via `AddExtensionOption` |
| `src/include/mongo_table_function.hpp` | Add `after_cluster_time` field to `MongoScanData` |
| `src/mongo_table_function.cpp` | Read named parameter in `MongoScanBind`, read session setting as fallback, apply `readConcern` in `MongoScanInitLocal` |
| `src/mongo_extension.cpp` | Add `after_cluster_time` to `mongo_scan.named_parameters` |

## User-Facing Documentation

The README and `LOAD mongo; SELECT * FROM duckdb_settings() WHERE name LIKE 'mongo%';` should make clear:

> **`mongo_after_cluster_time`** — Sets a MongoDB cluster timestamp for causal consistency reads. All subsequent `mongo_scan` queries will include `readConcern: { afterClusterTime: <value> }`, which tells MongoDB to wait until the cluster has advanced past this point before returning data. This is NOT time travel — the read returns current data, but guarantees it reflects all operations up to the given timestamp. Use `mongo_operation_time()` to capture the timestamp from a prior read.

## Edge Cases

- **Value 0 or NULL**: Treated as "no afterClusterTime" — same as not setting it
- **Standalone MongoDB**: `afterClusterTime` is ignored by the server (no cluster time on standalone)
- **Stale timestamp**: If the timestamp is from the future or very far in the past, MongoDB handles it gracefully — future timestamps may block until the cluster catches up, past timestamps return immediately
- **Legacy driver (3.x)**: `readConcern` with `afterClusterTime` is supported since MongoDB 3.6 and mongocxx 3.x
