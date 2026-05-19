# Implementation Plan: MongoDB Driver Compatibility Layer

## Phase 1: Legacy vcpkg Ports

Create the port definitions for the 1.x/3.x driver stack.

- [ ] Fetch SHA512 hashes for libbson 1.27.6, mongo-c-driver 1.27.6, mongo-cxx-driver 3.10.2 source tarballs
- [ ] Create `vendor/vcpkg/ports-legacy/libbson/vcpkg.json` (version 1.27.6) `@spec DRVCOMPAT-PORT-001`
- [ ] Create `vendor/vcpkg/ports-legacy/libbson/portfile.cmake` with correct CMake config paths (`bson-1.0`) `@spec DRVCOMPAT-PORT-001`
- [ ] Create `vendor/vcpkg/ports-legacy/mongo-c-driver/vcpkg.json` (version 1.27.6) `@spec DRVCOMPAT-PORT-002`
- [ ] Create `vendor/vcpkg/ports-legacy/mongo-c-driver/portfile.cmake` with correct CMake config paths (`mongoc-1.0`) `@spec DRVCOMPAT-PORT-002`
- [ ] Create `vendor/vcpkg/ports-legacy/mongo-cxx-driver/vcpkg.json` (version 3.10.2) `@spec DRVCOMPAT-PORT-003`
- [ ] Create `vendor/vcpkg/ports-legacy/mongo-cxx-driver/portfile.cmake` `@spec DRVCOMPAT-PORT-003`
- [ ] Add any needed patches for 1.x/3.x (e.g., include directory fixes) `@spec DRVCOMPAT-PORT-004`

## Phase 2: CMake & Makefile Integration

Wire up the build-time selection.

- [ ] Add `MONGOCXX_LEGACY` option to `CMakeLists.txt` `@spec DRVCOMPAT-BUILD-001`
- [ ] Add `VCPKG_OVERLAY_PORTS` logic for legacy port path `@spec DRVCOMPAT-BUILD-002`
- [ ] Add `add_compile_definitions(MONGOCXX_LEGACY)` when option is ON `@spec DRVCOMPAT-BUILD-001`
- [ ] Add `release-legacy` target to Makefile `@spec DRVCOMPAT-BUILD-006`
- [ ] Verify `find_package(bsoncxx)` and `find_package(mongocxx)` work with both stacks `@spec DRVCOMPAT-PORT-004`

## Phase 3: Compatibility Header & Source Fixes

Handle any API divergences discovered during compilation.

- [ ] Create `src/include/mongo_compat.hpp` with `#ifdef MONGOCXX_LEGACY` guards `@spec DRVCOMPAT-COMPAT-003`
- [ ] Attempt legacy build, catalog any compile errors
- [ ] Fix divergences in compat header (not in application code) `@spec DRVCOMPAT-COMPAT-003`
- [ ] Verify default build still compiles cleanly `@spec DRVCOMPAT-BUILD-005`

## Phase 4: Test & Verify

Confirm both builds work against their respective MongoDB versions.

- [ ] Build with `MONGOCXX_LEGACY=ON` compiles and links `@spec DRVCOMPAT-BUILD-004`
- [ ] Build with `MONGOCXX_LEGACY=OFF` compiles and links `@spec DRVCOMPAT-BUILD-005`
- [ ] Run `test/sql/query/basic.test` with legacy build against MongoDB 3.6 `@spec DRVCOMPAT-FUNC-001, DRVCOMPAT-FUNC-002`
- [ ] Run `test/sql/query/operation_time.test` with legacy build `@spec DRVCOMPAT-FUNC-005`
- [ ] Run full test suite with legacy build `@spec DRVCOMPAT-FUNC-001 through DRVCOMPAT-FUNC-005`

## Phase 5: Documentation

- [ ] Update `docs/IMPLEMENTATION.md` with driver compat layer details
- [ ] Update `README.md` with legacy build instructions

## Definition of Done

1. `make release` builds with 4.x drivers (existing behavior unchanged)
2. `make release-legacy` builds with 3.x/1.x drivers
3. Legacy build connects to MongoDB 3.6 and passes basic.test
4. No `#ifdef MONGOCXX_LEGACY` in application source files (only in `mongo_compat.hpp`)
5. All existing tests pass on both build configurations (against their respective MongoDB versions)
