# High-Level Design: MongoDB Driver Compatibility Layer

## Problem Statement

The duckdb-mongo extension currently uses mongo-c-driver 2.3.0 and mongo-cxx-driver 4.3.0, which require MongoDB 4.2+ (wire protocol version 8). This excludes users running MongoDB 3.6 (wire protocol version 6), which is still deployed in production environments.

The `MongoCollectionGenerator::EnsureCollectionsLoaded()` method catches driver exceptions silently, causing ATTACH to succeed but all table lookups to fail with "Table does not exist" — a confusing user experience.

## Goal

Support building the extension against **either** the modern driver stack (mongocxx 4.x / libmongoc 2.x) **or** the legacy driver stack (mongocxx 3.x / libmongoc 1.x) via a compile-time macro, so the same codebase can target MongoDB 3.6+ or MongoDB 4.2+ depending on the build configuration.

## Target Users

- Teams running legacy MongoDB 3.6 deployments who want to query data from DuckDB
- CI/test environments using older MongoDB versions
- Users on modern MongoDB who want the latest driver features

## Architecture Overview

### Dual Driver Support

```
Build-time selection via MONGOCXX_LEGACY macro:

  [default]   mongocxx 4.3.0  →  libmongoc 2.3.0  →  libbson 2.3.0
                                    (wire version >= 8, MongoDB 4.2+)

  -DMONGOCXX_LEGACY=1
              mongocxx 3.10.2 →  libmongoc 1.27.6 →  libbson 1.27.6
                                    (wire version >= 6, MongoDB 3.6+)
```

### Compatibility Layer Strategy

A single header (`src/include/mongo_compat.hpp`) provides macros and type aliases that abstract the differences between 3.x and 4.x. Application code uses the compat layer exclusively for any divergent APIs. Non-divergent APIs (the majority) are used directly.

### Components

1. **`src/include/mongo_compat.hpp`** — Compatibility header with `#ifdef MONGOCXX_LEGACY` guards
2. **vcpkg port definitions** — Ports for both 1.x/3.x and 2.x/4.x driver stacks
3. **CMakeLists.txt** — Conditional dependency selection based on `MONGOCXX_LEGACY`
4. **vcpkg.json / vcpkg-configuration.json** — Switchable manifests or feature flags
5. **C++ source** — Replace direct divergent API calls with compat layer calls

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Compile-time macro, not runtime detection | Zero overhead; driver ABI differs, can't link both |
| Default to 4.x (modern) | Existing behavior preserved; legacy is opt-in |
| Single compat header | Minimizes code churn; divergences are few |
| mongo-c-driver **1.27.6** for legacy | Last 1.x with wire version 6 (MongoDB 3.6) support |
| mongo-cxx-driver **3.10.2** for legacy | Last 3.x compatible with libmongoc >= 1.25.0 |

### API Divergences to Abstract

| Area | 4.x (modern) | 3.x (legacy) | Compat approach |
|------|--------------|---------------|-----------------|
| Value accessors | `get_string()` returns `std::string_view` directly | `get_string()` returns `b_string` with `.value` | Inline helper or macro |
| CMake targets | `mongo::mongocxx_static` | `mongo::mongocxx_static` (same in late 3.x) | Likely no change needed |
| Session API | Same | Same (available since 3.6+) | Direct use |
| Header paths | Same | Same | Direct use |
| Type enums | `k_string` only | `k_string` + deprecated `k_utf8` | Direct use (`k_string` works in both) |

### Risk Assessment

- **Low risk**: Header paths, type enums, builder APIs, session APIs — identical across versions
- **Medium risk**: Value accessor return types — need compat wrappers
- **Low risk**: CMake target names — same in mongocxx >= 3.7

## Non-Goals

- Runtime wire version detection/fallback
- Supporting MongoDB versions older than 3.6
- Maintaining two separate codebases
