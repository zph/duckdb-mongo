# EARS Specifications: MongoDB Driver Compatibility Layer

## Build System

### DRVCOMPAT-BUILD-001
When `MONGOCXX_LEGACY` CMake option is ON, the system shall compile all source files with the `MONGOCXX_LEGACY` preprocessor definition.

### DRVCOMPAT-BUILD-002
When `MONGOCXX_LEGACY` CMake option is ON, the system shall use vcpkg overlay ports from `vendor/vcpkg/ports-legacy/` to resolve `libbson`, `mongo-c-driver`, and `mongo-cxx-driver` dependencies.

### DRVCOMPAT-BUILD-003
When `MONGOCXX_LEGACY` CMake option is OFF (default), the system shall use the existing vcpkg ports from `vendor/vcpkg/ports/` (mongocxx 4.3.0 / libmongoc 2.3.0 / libbson 2.3.0).

### DRVCOMPAT-BUILD-004
The system shall successfully compile and link with mongocxx 3.10.2, libmongoc 1.27.6, and libbson 1.27.6 when `MONGOCXX_LEGACY=ON`.

### DRVCOMPAT-BUILD-005
The system shall successfully compile and link with mongocxx 4.3.0, libmongoc 2.3.0, and libbson 2.3.0 when `MONGOCXX_LEGACY=OFF`.

### DRVCOMPAT-BUILD-006
The Makefile shall provide a `release-legacy` target that builds the extension with `MONGOCXX_LEGACY=ON`.

## Compatibility

### DRVCOMPAT-COMPAT-001
When built with `MONGOCXX_LEGACY=ON`, the extension shall connect to MongoDB 3.6+ servers (wire protocol version 6+).

### DRVCOMPAT-COMPAT-002
When built with `MONGOCXX_LEGACY=OFF`, the extension shall connect to MongoDB 4.2+ servers (wire protocol version 8+).

### DRVCOMPAT-COMPAT-003
The `mongo_compat.hpp` header shall provide compile-time abstractions for any API divergences between mongocxx 3.x and 4.x, so that application source files do not contain `#ifdef MONGOCXX_LEGACY` guards (except in `mongo_compat.hpp` itself).

## Functional Parity

### DRVCOMPAT-FUNC-001
When built with `MONGOCXX_LEGACY=ON`, the `mongo_scan` table function shall return identical results to the default build for the same MongoDB data.

### DRVCOMPAT-FUNC-002
When built with `MONGOCXX_LEGACY=ON`, the ATTACH mechanism shall discover and list all collections in a MongoDB database.

### DRVCOMPAT-FUNC-003
When built with `MONGOCXX_LEGACY=ON`, filter pushdown shall generate the same MongoDB query documents as the default build.

### DRVCOMPAT-FUNC-004
When built with `MONGOCXX_LEGACY=ON`, schema inference shall produce identical column types and names as the default build for the same data.

### DRVCOMPAT-FUNC-005
When built with `MONGOCXX_LEGACY=ON`, the `client_session` and `operation_time()` APIs shall function correctly for operation time tracking.

## vcpkg Ports

### DRVCOMPAT-PORT-001
The `vendor/vcpkg/ports-legacy/libbson/` port shall build libbson 1.27.6 from the mongodb/mongo-c-driver repository at ref `1.27.6`.

### DRVCOMPAT-PORT-002
The `vendor/vcpkg/ports-legacy/mongo-c-driver/` port shall build libmongoc 1.27.6 from the mongodb/mongo-c-driver repository at ref `1.27.6`.

### DRVCOMPAT-PORT-003
The `vendor/vcpkg/ports-legacy/mongo-cxx-driver/` port shall build mongocxx 3.10.2 from the mongodb/mongo-cxx-driver repository at ref `r3.10.2`.

### DRVCOMPAT-PORT-004
Each legacy port shall export the same CMake package names (`bsoncxx`, `mongocxx`, `bson-*`, `mongoc-*`) so that `find_package` calls in CMakeLists.txt work without modification.
