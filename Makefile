PROJ_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

EXT_NAME=mongo
EXT_CONFIG=${PROJ_DIR}extension_config.cmake

include extension-ci-tools/makefiles/duckdb_extension.Makefile

# @spec DRVCOMPAT-BUILD-006
# Legacy build targets for MongoDB 3.6+ support (mongocxx 3.x / libmongoc 1.x)
# VCPKG_OVERLAY_PORTS must be passed on the cmake command line (not inside CMakeLists.txt)
# because vcpkg resolves packages during the initial project() call in DuckDB's CMakeLists.txt.
LEGACY_VCPKG_TOOLCHAIN=${PROJ_DIR}vendor/vcpkg/scripts/buildsystems/vcpkg.cmake
LEGACY_FLAGS=-DMONGOCXX_LEGACY=ON -DVCPKG_BUILD=1 -DCMAKE_TOOLCHAIN_FILE='${LEGACY_VCPKG_TOOLCHAIN}' -DVCPKG_OVERLAY_PORTS='${PROJ_DIR}vendor/vcpkg/ports-legacy' -DVCPKG_MANIFEST_DIR='${PROJ_DIR}'

release-legacy: ## Build release with legacy MongoDB driver (3.6+ support)
	mkdir -p build/release
	cmake $(GENERATOR) $(BUILD_FLAGS) $(EXT_RELEASE_FLAGS) $(LEGACY_FLAGS) -DCMAKE_BUILD_TYPE=Release -S $(DUCKDB_SRCDIR) -B build/release
	cmake --build build/release --config Release

debug-legacy: ## Build debug with legacy MongoDB driver (3.6+ support)
	mkdir -p build/debug
	cmake $(GENERATOR) $(BUILD_FLAGS) $(EXT_DEBUG_FLAGS) $(LEGACY_FLAGS) -DCMAKE_BUILD_TYPE=Debug -S $(DUCKDB_SRCDIR) -B build/debug
	cmake --build build/debug --config Debug

.PHONY: help release-legacy debug-legacy

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'
