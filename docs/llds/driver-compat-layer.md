# Low-Level Design: MongoDB Driver Compatibility Layer

## Overview

Provide build-time selection between mongocxx 4.x (modern, MongoDB 4.2+) and mongocxx 3.x (legacy, MongoDB 3.6+) via a `MONGOCXX_LEGACY` CMake option. The codebase uses 3.x-compatible APIs already (`.value` accessor pattern), so the compat layer is thin.

## Component 1: CMake Build System

### CMakeLists.txt Changes

Add a `MONGOCXX_LEGACY` option that controls:
- Which vcpkg manifest overlay is active (or which feature is selected)
- A compile definition `MONGOCXX_LEGACY` passed to all source files

```cmake
option(MONGOCXX_LEGACY "Build with mongocxx 3.x / libmongoc 1.x for MongoDB 3.6+ support" OFF)

if(MONGOCXX_LEGACY)
    add_compile_definitions(MONGOCXX_LEGACY)
endif()
```

The `find_package` calls remain the same — both driver versions export `bsoncxx` and `mongocxx` CMake packages. The CMake target names are identical in late 3.x and 4.x (`mongo::mongocxx_static`, `mongo::bsoncxx_static`).

## Component 2: vcpkg Port Definitions

### Strategy: Separate Port Directories for Legacy

Create legacy port directories alongside the existing ones:

```
vendor/vcpkg/ports/
  libbson/              (2.3.0 - existing)
  libbson-legacy/       (1.27.6 - new)
  mongo-c-driver/       (2.3.0 - existing)
  mongo-c-driver-legacy/ (1.27.6 - new)
  mongo-cxx-driver/     (4.3.0 - existing)
  mongo-cxx-driver-legacy/ (3.10.2 - new)
```

### Approach: vcpkg Feature Flag in vcpkg.json

Use the top-level `vcpkg.json` to select which set of ports to use. Since vcpkg doesn't natively support "either/or" dependencies cleanly, the simplest approach is **two vcpkg.json manifests** selected by CMake:

- `vcpkg.json` (default) — points to modern 4.x ports
- `vcpkg-legacy.json` — points to legacy 3.x ports with renamed port names

However, this is complex. A simpler approach: **use overlay ports**.

### Recommended Approach: Overlay Ports

When `MONGOCXX_LEGACY=ON`, swap the port definitions via CMake's `VCPKG_OVERLAY_PORTS`:

```cmake
if(MONGOCXX_LEGACY)
    set(VCPKG_OVERLAY_PORTS "${CMAKE_SOURCE_DIR}/vendor/vcpkg/ports-legacy")
endif()
```

Create a `vendor/vcpkg/ports-legacy/` directory with `libbson/`, `mongo-c-driver/`, and `mongo-cxx-driver/` subdirectories containing portfiles for the 1.x/3.x versions. The port **names** remain the same, so no changes to `vcpkg.json` or `find_package` calls.

### Legacy Port: libbson (1.27.6)

Key differences from 2.3.0 port:
- **Source**: Same repo (mongodb/mongo-c-driver), ref `1.27.6`
- **SHA512**: New hash for 1.27.6 tarball
- **CMake config path**: `lib/cmake/bson-1.0` (1.x uses `bson-1.0`, not `bson-2.3.0`)
- **Static macro header**: `bson/bson-macros.h` (1.x) vs `bson/macros.h` (2.x)
- **Patch**: `fix-include-directory.patch` needs adaptation for 1.x directory structure

### Legacy Port: mongo-c-driver (1.27.6)

Key differences from 2.3.0 port:
- **Source**: Same repo, ref `1.27.6`
- **SHA512**: New hash
- **CMake config path**: `lib/cmake/mongoc-1.0` (1.x) vs `mongoc-2.3.0` (2.x)
- **Static macro header**: `mongoc/mongoc-macros.h` (same in both)
- **Patches**: May need adaptation — the CMake build system in 1.x is slightly different
- **pkgconfig**: `libmongoc-static-1.0.pc` (1.x) vs `mongoc2-static.pc` (2.x)

### Legacy Port: mongo-cxx-driver (3.10.2)

Key differences from 4.3.0 port:
- **Source**: Same repo, ref `r3.10.2`
- **SHA512**: New hash
- **CMake config path**: `lib/cmake/bsoncxx-3.10.2` and `lib/cmake/mongocxx-3.10.2`
- **VERSION_CURRENT**: Still needs to be written
- **Patch**: `fix-dependencies.patch` needs adaptation for 3.x build system

## Component 3: Compatibility Header (mongo_compat.hpp)

Based on the API audit, the codebase already uses the `.value` accessor pattern that works in both 3.x and 4.x. The compat header handles the few remaining divergences.

### Known Divergences

1. **`bsoncxx::types::bson_value::value` constructor** — In 3.x, constructed from `bsoncxx::types::value` (a view type); in 4.x from `bsoncxx::types::bson_value::view`. Verify if the current code compiles as-is with 3.x.

2. **`mongocxx::pipeline::append_stage`** — Available in both, but verify signature.

3. **`client_session::operation_time()`** — Returns `bsoncxx::types::b_timestamp` in both, but verify the struct layout.

4. **`list_database_names()` / `list_collection_names()`** — Both return `std::vector<std::string>` in 3.x and 4.x. No compat needed.

### Header Structure

```cpp
// src/include/mongo_compat.hpp
#pragma once

// Detect driver version at compile time
#ifdef MONGOCXX_LEGACY
// mongocxx 3.x / libmongoc 1.x
// Add any 3.x-specific workarounds here
#else
// mongocxx 4.x / libmongoc 2.x (default)
#endif
```

Given the audit shows near-complete API compatibility, this header may remain mostly empty — it exists as the designated place for any divergences discovered during compilation.

## Component 4: Baseline Version Updates

### vendor/vcpkg/versions/baseline.json

No changes needed for the default path. The legacy overlay ports override at the vcpkg layer.

For the legacy ports overlay, each port's `vcpkg.json` specifies version `1.27.6` / `3.10.2`.

## Build & Test Matrix

| Configuration | Driver Stack | Min MongoDB | Build Command |
|---|---|---|---|
| Default | mongocxx 4.3.0 / libmongoc 2.3.0 | 4.2 | `make release` |
| Legacy | mongocxx 3.10.2 / libmongoc 1.27.6 | 3.6 | `make release MONGOCXX_LEGACY=1` |

## Risk Mitigation

1. **SHA512 hashes**: Must be computed from actual GitHub release tarballs
2. **Patch compatibility**: Existing patches are for 2.x/4.x source trees; legacy ports need fresh patches (or none if the 1.x/3.x sources don't need them)
3. **CMake config names**: The `find_package` and `vcpkg_cmake_config_fixup` paths differ between 1.x and 2.x — this is the most likely source of build errors
4. **CI**: Both configurations should be tested in CI

## Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `CMakeLists.txt` | Modify | Add `MONGOCXX_LEGACY` option and compile definition |
| `Makefile` | Modify | Add `release-legacy` target |
| `src/include/mongo_compat.hpp` | Create | Compatibility header (thin) |
| `vendor/vcpkg/ports-legacy/libbson/` | Create | 1.27.6 portfiles |
| `vendor/vcpkg/ports-legacy/mongo-c-driver/` | Create | 1.27.6 portfiles |
| `vendor/vcpkg/ports-legacy/mongo-cxx-driver/` | Create | 3.10.2 portfiles |
