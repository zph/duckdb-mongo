# Implementation Plan: Read Preference

## Phase 1: Parsing Utility

- [ ] Add `ParseReadPreference(const string &input) -> mongocxx::read_preference::read_mode` to `mongo_compat.hpp` `@spec RP-PARAM-002`
  - Accept camelCase: `primary`, `primaryPreferred`, `secondary`, `secondaryPreferred`, `nearest`
  - Accept snake_case: `primary_preferred`, `secondary_preferred`
  - Case-insensitive
  - Throw `InvalidInputException` on unknown values `@spec RP-PARAM-003`
  - Return empty optional for empty/NULL input `@spec RP-PARAM-004`

## Phase 2: Session Setting

- [ ] Register `mongo_read_preference` via `AddExtensionOption` in `mongo_extension.cpp` `@spec RP-SET-001`
  - Type: VARCHAR, Scope: SESSION, Default: empty
- [ ] Verify visible in `duckdb_settings()` `@spec RP-SET-004`
- [ ] Verify `RESET` clears it `@spec RP-SET-003`

## Phase 3: Named Parameter

- [ ] Add `read_preference` to `mongo_scan.named_parameters` in `mongo_extension.cpp` (type VARCHAR) `@spec RP-PARAM-001`
- [ ] Add `string read_preference_str` field to `MongoScanData` in `mongo_table_function.hpp` `@spec RP-PARAM-001`
- [ ] Parse the parameter in `MongoScanBind` `@spec RP-PARAM-001, RP-PARAM-002`

## Phase 4: Apply to MongoDB Queries

- [ ] In `MongoScanInitLocal`, resolve effective read preference `@spec RP-PREC-001, RP-PREC-002, RP-PREC-003`
  - Check `MongoScanData.read_preference_str` first (named parameter)
  - Fall back to `current_setting('mongo_read_preference')`
  - If both empty, skip (use connection default)
- [ ] Construct `mongocxx::read_preference` and set on `mongocxx::options::find` `@spec RP-PARAM-001`
- [ ] Construct `mongocxx::read_preference` and set on `mongocxx::options::aggregate` `@spec RP-PARAM-001`
- [ ] Verify works alongside `afterClusterTime` `@spec RP-COMPOSE-001`

## Phase 5: Tests

- [ ] Test: setting visible in `duckdb_settings()` `@spec RP-SET-004`
- [ ] Test: SET/RESET cycle `@spec RP-SET-001, RP-SET-002, RP-SET-003`
- [ ] Test: named parameter with `primary` works `@spec RP-PARAM-001`
- [ ] Test: named parameter with `secondaryPreferred` works `@spec RP-PARAM-001, RP-PARAM-002`
- [ ] Test: snake_case `secondary_preferred` accepted `@spec RP-PARAM-002`
- [ ] Test: invalid value raises error `@spec RP-PARAM-003`
- [ ] Test: empty string means use default `@spec RP-PARAM-004`
- [ ] Test: SET applies to ATTACH queries `@spec RP-ATTACH-001`
- [ ] Test: combined with `after_cluster_time` `@spec RP-COMPOSE-001`

## Phase 6: Documentation

- [ ] Add read preference section to README with examples
- [ ] Update `docs/IMPLEMENTATION.md` with architecture
- [ ] Update `docs/high-level-design.md` features list

## Definition of Done

1. `SET mongo_read_preference = 'secondaryPreferred'` applies to all subsequent reads
2. `mongo_scan(..., read_preference := 'secondary')` applies to that specific call
3. Named parameter overrides session setting
4. Both camelCase and snake_case accepted, case-insensitive
5. Empty/NULL means use connection default
6. Invalid input raises descriptive error
7. Composes with afterClusterTime
8. Works on both legacy (3.x) and modern (4.x) driver builds
9. All sqllogictests pass
