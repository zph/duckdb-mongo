#pragma once

// Compatibility layer for:
// 1. DuckDB v1.5.x vs main branch API differences (auto-detected via __has_include)
// 2. MongoDB driver version: mongocxx 4.x (default) vs 3.x (legacy, -DMONGOCXX_LEGACY=ON)
//
// @spec DRVCOMPAT-COMPAT-003

#include "duckdb/common/types/vector.hpp"
#include "duckdb/planner/table_filter.hpp"

// FlatVector was moved to a separate header on DuckDB main.
#if __has_include("duckdb/common/vector/flat_vector.hpp")
#include "duckdb/common/vector/flat_vector.hpp"
#endif

// --- Vector API compatibility ---
// DuckDB main removed GetAuxiliary(), renamed Initialize(bool) to Initialize(enum),
// made FlatVector::GetData return const, and added count_t param to Reference(Value).
#if __has_include("duckdb/common/types/size.hpp")
#include "duckdb/common/types/size.hpp"
#define DUCKDB_MAIN_VECTOR_API 1
#endif

#ifdef DUCKDB_MAIN_VECTOR_API
#include "duckdb/planner/filter/expression_filter.hpp"
// DuckDB main: bound_comparison_expression.hpp is transitively included above.
#else
// DuckDB v1.5.x: include explicitly so MongoIsComparisonExpr / MongoComparisonLeft/Right are available.
#include "duckdb/planner/expression/bound_comparison_expression.hpp"
#endif

// DuckDB main made BoundSimpleFunction::name protected; use GetName() accessor.
#ifdef DUCKDB_MAIN_VECTOR_API
#define MONGO_FUNCTION_NAME(func) ((func).GetName())
#else
#define MONGO_FUNCTION_NAME(func) ((func).name)
#endif

namespace duckdb {

// Check if a vector has an auxiliary buffer.
inline bool MongoVectorHasAuxiliary(Vector &vec) {
#ifdef DUCKDB_MAIN_VECTOR_API
	return vec.GetBufferRef().get() != nullptr;
#else
	return vec.GetAuxiliary().get() != nullptr;
#endif
}

// Initialize a vector without zeroing memory.
inline void MongoVectorInitializeUninitialized(Vector &vec, idx_t capacity = STANDARD_VECTOR_SIZE) {
#ifdef DUCKDB_MAIN_VECTOR_API
	vec.Initialize(VectorDataInitialization::UNINITIALIZED, capacity);
#else
	vec.Initialize(false, capacity);
#endif
}

// Get a mutable data pointer from a flat vector.
template <typename T>
inline T *MongoFlatVectorGetDataMutable(Vector &vec) {
#ifdef DUCKDB_MAIN_VECTOR_API
	return FlatVector::GetDataMutable<T>(vec);
#else
	return FlatVector::GetData<T>(vec);
#endif
}

// Reference a single Value in a vector.
inline void MongoVectorReferenceSingleValue(Vector &vec, const Value &val) {
#ifdef DUCKDB_MAIN_VECTOR_API
	vec.Reference(val, count_t(1));
#else
	vec.Reference(val);
#endif
}

// Set a flat vector's tracked size (DuckDB main tracks per-vector sizes for DataChunk::Verify).
inline void MongoSetVectorSize(Vector &vec, idx_t size) {
#ifdef DUCKDB_MAIN_VECTOR_API
	FlatVector::SetSize(vec, size);
#endif
}

// Copy a single TableFilter (DuckDB main removed TableFilter::Copy(); only ExpressionFilter::Copy() remains).
inline unique_ptr<TableFilter> MongoCopyFilter(const TableFilter &filter) {
#ifdef DUCKDB_MAIN_VECTOR_API
	auto &ef = static_cast<const ExpressionFilter &>(filter);
	return ef.Copy();
#else
	return filter.Copy();
#endif
}

// Cross-version comparison expression helpers.
// DuckDB main: comparisons are BoundFunctionExpression; v1.5.x: BoundComparisonExpression.
inline bool MongoIsComparisonExpr(const Expression &expr) {
#ifdef DUCKDB_MAIN_VECTOR_API
	return BoundComparisonExpression::IsComparison(expr);
#else
	return expr.GetExpressionClass() == ExpressionClass::BOUND_COMPARISON;
#endif
}

inline const Expression &MongoComparisonLeft(const Expression &expr) {
#ifdef DUCKDB_MAIN_VECTOR_API
	return BoundComparisonExpression::Left(expr.Cast<BoundFunctionExpression>());
#else
	return *expr.Cast<BoundComparisonExpression>().left;
#endif
}

inline const Expression &MongoComparisonRight(const Expression &expr) {
#ifdef DUCKDB_MAIN_VECTOR_API
	return BoundComparisonExpression::Right(expr.Cast<BoundFunctionExpression>());
#else
	return *expr.Cast<BoundComparisonExpression>().right;
#endif
}

// DuckDB main made Expression::return_type and BaseExpression::type protected.
// Provide accessor helpers that compile on both v1.5.x (public fields) and main (getters).
#ifdef DUCKDB_MAIN_VECTOR_API
#define MONGO_EXPR_RETURN_TYPE(expr) ((expr).GetReturnType())
#define MONGO_EXPR_TYPE(expr)        ((expr).GetExpressionType())
#else
#define MONGO_EXPR_RETURN_TYPE(expr) ((expr).return_type)
#define MONGO_EXPR_TYPE(expr)        ((expr).GetExpressionType())
#endif

// --- afterClusterTime parsing utility ---
// @spec ACT-PARAM-002, ACT-PARAM-003, ACT-PARAM-004
// Parses a cluster time value from either:
//   - UBIGINT-as-string: "7641659143652114433"
//   - seconds:increment format: "1779206684:15"
// Returns 0 for empty/NULL input (meaning disabled).
// Throws InvalidInputException on malformed input.
inline uint64_t ParseAfterClusterTime(const string &input) {
	if (input.empty()) {
		return 0;
	}
	auto colon_pos = input.find(':');
	if (colon_pos != string::npos) {
		// seconds:increment format
		try {
			uint64_t seconds = std::stoull(input.substr(0, colon_pos));
			uint64_t increment = std::stoull(input.substr(colon_pos + 1));
			if (seconds > UINT32_MAX || increment > UINT32_MAX) {
				throw InvalidInputException("after_cluster_time '%s': seconds and increment must fit in 32 bits", input);
			}
			return (seconds << 32) | increment;
		} catch (const InvalidInputException &) {
			throw;
		} catch (...) {
			throw InvalidInputException(
			    "after_cluster_time '%s': expected 'seconds:increment' format (e.g., '1779206684:15')", input);
		}
	}
	// Plain UBIGINT string
	try {
		return std::stoull(input);
	} catch (...) {
		throw InvalidInputException(
		    "after_cluster_time '%s': expected a UBIGINT or 'seconds:increment' format", input);
	}
}

} // namespace duckdb

// --- MongoDB driver compatibility (mongocxx 4.x vs 3.x) ---
// The codebase already uses the 3.x-compatible .value accessor pattern
// (e.g., get_string().value, get_int32().value, get_document().value),
// which works identically in both 3.x and 4.x.
//
// Add any driver-version-specific workarounds below as needed.
#ifdef MONGOCXX_LEGACY
// mongocxx 3.x / libmongoc 1.x (MongoDB 3.6+ support)
#endif
