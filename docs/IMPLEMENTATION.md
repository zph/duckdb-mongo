# Implementation Notes

## MongoDB Driver Compatibility Layer

### Overview

The extension supports building against either the modern driver stack (mongocxx 4.x / libmongoc 2.x, MongoDB 4.2+) or the legacy driver stack (mongocxx 3.x / libmongoc 1.x, MongoDB 3.6+) via a compile-time `MONGOCXX_LEGACY` CMake option.

### Build Commands

| Configuration | Driver Stack | Min MongoDB | Command |
|---|---|---|---|
| Default | mongocxx 4.3.0 / libmongoc 2.3.0 | 4.2 | `make release` |
| Legacy | mongocxx 3.10.2 / libmongoc 1.27.6 | 3.6 | `make release-legacy` |

### Architecture

```
Build-time selection via MONGOCXX_LEGACY:

  [default]       mongocxx 4.3.0  → libmongoc 2.3.0  → libbson 2.3.0
                  vendor/vcpkg/ports/

  MONGOCXX_LEGACY mongocxx 3.10.2 → libmongoc 1.27.6 → libbson 1.27.6
                  vendor/vcpkg/ports-legacy/
```

The Makefile passes `-DVCPKG_OVERLAY_PORTS=vendor/vcpkg/ports-legacy` to swap the port definitions at cmake configure time. Port names remain identical so `find_package` calls don't change.

### Key Files

| File | Role |
|------|------|
| `Makefile` | `release-legacy` / `debug-legacy` targets with `LEGACY_FLAGS` |
| `CMakeLists.txt` | `MONGOCXX_LEGACY` option, `add_compile_definitions(MONGOCXX_LEGACY)` |
| `src/include/mongo_compat.hpp` | Compatibility header (DuckDB version + MongoDB driver) |
| `vendor/vcpkg/ports-legacy/libbson/` | libbson 1.27.6 port |
| `vendor/vcpkg/ports-legacy/mongo-c-driver/` | libmongoc 1.27.6 port |
| `vendor/vcpkg/ports-legacy/mongo-cxx-driver/` | mongocxx 3.10.2 port |

### Design Decisions

- **Compile-time macro, not runtime detection**: Zero overhead; driver ABI differs so both can't be linked.
- **Default to 4.x**: Existing behavior preserved; legacy is opt-in.
- **Overlay ports with same names**: `find_package(bsoncxx)` and `find_package(mongocxx)` work unchanged.
- **Codebase uses 3.x-compatible API**: The `.value` accessor pattern (`get_string().value`, `get_int32().value`) works identically in both 3.x and 4.x.

### Known Differences on MongoDB 3.6

- Numbers may be inferred as DOUBLE instead of BIGINT (MongoDB 3.6 stores all numbers as doubles by default).
- Standalone MongoDB 3.6 does not support sessions — `operationTime` tracking is unavailable.

---

## Operation Time Tracking

### Overview

Exposes MongoDB's `operationTime` from server responses as DuckDB scalar functions, enabling causal consistency workflows and operation correlation.

### Architecture

```
mongo_scan (table function)
  ├── MongoScanInitLocal: starts mongocxx::client_session (if supported), passes to find()/aggregate()
  ├── MongoScanFunction: iterates cursor, on completion reads session.operation_time()
  └── Stores b_timestamp in MongoOperationState on ClientContext::registered_state
         │
         ▼
mongo_operation_time()      → reads UBIGINT from MongoOperationState
mongo_operation_timestamp() → extracts upper 32 bits → Timestamp::FromEpochSeconds()
mongo_operation_increment() → extracts lower 32 bits
```

### Key Files

| File | Role |
|------|------|
| `src/include/mongo_operation_state.hpp` | `MongoOperationState` — per-connection state extending `ClientContextState` |
| `src/include/mongo_table_function.hpp` | `MongoScanState.session` — `unique_ptr<mongocxx::client_session>` |
| `src/mongo_table_function.cpp` | Session lifecycle: start in init (with fallback), pass to find/aggregate, capture on cursor exhaustion |
| `src/mongo_extension.cpp` | Scalar function registration for all three helpers |
| `test/sql/query/operation_time.test` | DuckDB sqllogictest covering function existence, NULL-before-scan, types, and decomposition |

### Design Decisions

- **Per-connection via `ClientContext::registered_state`**: Avoids global state; each DuckDB connection tracks its own last operation time. Thread-safe via mutex in `MongoOperationState`.
- **Captured on cursor exhaustion**: The operation time is written when `state.finished = true`, meaning the cursor has been fully consumed. This ensures the timestamp reflects the complete operation, not a partial read.
- **UBIGINT encoding**: The raw BSON timestamp packs epoch seconds (upper 32) and increment (lower 32) into a single `uint64_t`. This preserves the MongoDB wire format and makes direct integer comparison equivalent to chronological ordering.
- **NULL before first scan**: All three functions return NULL if no scan has run, rather than zero or an error.
- **Session fallback for standalone servers**: `start_session()` is wrapped in try-catch. On standalone MongoDB (which doesn't support sessions), the session is null and find/aggregate proceed without it. Operation time functions remain NULL.
- **Zero operationTime treated as absent**: Standalone servers return `{0, 0}` for operation_time even when sessions work. `SetOperationTime` ignores zero values to keep functions returning NULL rather than epoch-zero.
- **`mongocxx::client_session`**: Used instead of raw command inspection because the C++ driver's session API natively tracks `operationTime` across all operations routed through it.
