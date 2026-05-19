#pragma once

#include "duckdb.hpp"
#include "duckdb/main/client_context_state.hpp"
#include <mutex>

namespace duckdb {

// Per-connection state that stores the most recent MongoDB operationTime.
// Registered on ClientContext so that the mongo_operation_time() scalar function
// can read the timestamp captured by the last mongo_scan execution.
struct MongoOperationState : public ClientContextState {
	static constexpr const char *STATE_KEY = "mongo_operation_time";

	std::mutex lock;
	// BSON timestamp is a 64-bit value: upper 32 bits = seconds since epoch,
	// lower 32 bits = ordinal increment within that second.
	uint64_t operation_timestamp = 0;
	bool has_value = false;

	void SetOperationTime(uint32_t timestamp, uint32_t increment) {
		std::lock_guard<std::mutex> guard(lock);
		// Standalone MongoDB servers (non-replica-set) don't track operationTime
		// and return {0, 0}. Treat this as "no operation time available".
		if (timestamp == 0 && increment == 0) {
			return;
		}
		operation_timestamp = (static_cast<uint64_t>(timestamp) << 32) | static_cast<uint64_t>(increment);
		has_value = true;
	}

	bool GetOperationTime(uint64_t &result) {
		std::lock_guard<std::mutex> guard(lock);
		if (!has_value) {
			return false;
		}
		result = operation_timestamp;
		return true;
	}
};

} // namespace duckdb
