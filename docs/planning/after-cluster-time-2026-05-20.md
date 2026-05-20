# Implementation Plan: afterClusterTime / Causal Consistency Reads

## Phase 1: Timestamp Parsing Utility

Shared logic for both the named parameter and SET paths.

- [ ] Create `ParseAfterClusterTime(const string &input) -> uint64_t` utility in `mongo_compat.hpp` or a new `mongo_utils.hpp` `@spec ACT-PARAM-002`
  - Accepts UBIGINT-as-string (e.g., `"7641659143652114433"`)
  - Accepts `seconds:increment` format (e.g., `"1779206684:15"`)
  - Returns 0 for empty/NULL
  - Throws `InvalidInputException` on bad input `@spec ACT-PARAM-003`
- [ ] Write unit-style sqllogictest for parsing edge cases `@spec ACT-PARAM-003, ACT-PARAM-004`

## Phase 2: Session Setting (SET)

Register the extension option so ATTACH workflows get causal consistency.

- [ ] Register `mongo_after_cluster_time` via `AddExtensionOption` in `mongo_extension.cpp` `@spec ACT-SET-001`
  - Type: VARCHAR (to accept both formats)
  - Scope: SESSION
  - Default: empty string (disabled)
- [ ] Verify visible in `duckdb_settings()` `@spec ACT-SET-004`
- [ ] Verify `RESET mongo_after_cluster_time` clears it `@spec ACT-SET-003`
- [ ] Write sqllogictest for SET/RESET/visibility `@spec ACT-SET-001, ACT-SET-003, ACT-SET-004`

## Phase 3: Named Parameter on mongo_scan

Per-call explicit control.

- [ ] Add `after_cluster_time` to `mongo_scan.named_parameters` in `mongo_extension.cpp` (type VARCHAR) `@spec ACT-PARAM-001`
- [ ] Add `uint64_t after_cluster_time` field to `MongoScanData` in `mongo_table_function.hpp` `@spec ACT-PARAM-001`
- [ ] Parse the parameter in `MongoScanBind` using the Phase 1 utility `@spec ACT-PARAM-001, ACT-PARAM-002`
- [ ] Write sqllogictest for named parameter with UBIGINT and string inputs `@spec ACT-PARAM-001, ACT-PARAM-002`

## Phase 4: Apply readConcern to MongoDB Queries

Wire the parsed value into the actual MongoDB commands.

- [ ] In `MongoScanInitLocal`, resolve the effective `afterClusterTime` `@spec ACT-PREC-001, ACT-PREC-002, ACT-PREC-003`
  - Check `MongoScanData.after_cluster_time` first (named parameter)
  - Fall back to `current_setting('mongo_after_cluster_time')` from context
  - If both are 0/empty, skip
- [ ] Construct `mongocxx::read_concern` with `afterClusterTime` BSON timestamp `@spec ACT-PARAM-001`
  - Split UBIGINT: `t = value >> 32`, `i = value & 0xFFFFFFFF`
  - Set on `find_options` or `aggregate_options`
- [ ] Pass read concern to `collection.find()` and `collection.aggregate()` `@spec ACT-PARAM-001, ACT-ATTACH-001`
- [ ] Verify session-less path (standalone) doesn't error `@spec ACT-COMPAT-001`

## Phase 5: Tests

End-to-end verification against MongoDB.

- [ ] Test: `mongo_scan` with `after_cluster_time := (SELECT mongo_operation_time())` returns results `@spec ACT-COMPOSE-001`
- [ ] Test: `mongo_scan` with `after_cluster_time := '1779206684:15'` string format `@spec ACT-COMPOSE-002`
- [ ] Test: `SET mongo_after_cluster_time` then query via ATTACH `@spec ACT-ATTACH-001, ACT-SET-002`
- [ ] Test: named parameter overrides session setting `@spec ACT-PREC-001`
- [ ] Test: `RESET` clears the setting and subsequent reads have no afterClusterTime `@spec ACT-PREC-003`
- [ ] Test: invalid input raises error `@spec ACT-PARAM-003`
- [ ] Test: 0 / empty means disabled `@spec ACT-PARAM-004`

## Phase 6: Documentation

- [ ] Add afterClusterTime section to README with workflow examples `@spec ACT-DOC-001, ACT-DOC-002`
- [ ] Add causal consistency (NOT time travel) disclaimer `@spec ACT-DOC-001`
- [ ] Update `docs/IMPLEMENTATION.md` with afterClusterTime architecture
- [ ] Update `docs/high-level-design.md` features list

## Definition of Done

1. `SET mongo_after_cluster_time = <value>` applies to all subsequent ATTACH reads
2. `mongo_scan(..., after_cluster_time := <value>)` applies to that specific call
3. Named parameter overrides session setting
4. Both UBIGINT and `seconds:increment` string formats accepted
5. `RESET` clears the setting
6. Invalid input raises descriptive error
7. Works on both legacy (3.x) and modern (4.x) driver builds
8. Standalone MongoDB doesn't error
9. README documents the feature with "NOT time travel" disclaimer
10. All sqllogictests pass on both driver builds
