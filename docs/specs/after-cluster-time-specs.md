# EARS Specifications: afterClusterTime / Causal Consistency Reads

## Named Parameter (mongo_scan)

### ACT-PARAM-001
When `after_cluster_time` named parameter is provided as a UBIGINT to `mongo_scan`, the system shall include `readConcern: { afterClusterTime: <BsonTimestamp> }` in the MongoDB `find()` or `aggregate()` command.

### ACT-PARAM-002
When `after_cluster_time` named parameter is provided as a VARCHAR in `seconds:increment` format (e.g., `'1779206684:15'`), the system shall parse it into the equivalent UBIGINT `(seconds << 32) | increment` and apply it as the `afterClusterTime` read concern.

### ACT-PARAM-003
When `after_cluster_time` named parameter is provided with an unparseable VARCHAR value, the system shall raise an `InvalidInputException` with a descriptive error message.

### ACT-PARAM-004
When `after_cluster_time` is 0 or NULL, the system shall not include `afterClusterTime` in the read concern.

## Session Setting

### ACT-SET-001
The system shall register a `mongo_after_cluster_time` extension option of type VARCHAR with session scope and empty default value.

### ACT-SET-002
When `SET mongo_after_cluster_time = <value>` is executed, the system shall accept either a UBIGINT-as-string or a `seconds:increment` string.

### ACT-SET-003
When `RESET mongo_after_cluster_time` is executed, the system shall clear the session-level afterClusterTime so subsequent reads do not include it.

### ACT-SET-004
The `mongo_after_cluster_time` setting shall be visible in `SELECT * FROM duckdb_settings() WHERE name LIKE 'mongo%'`.

## Precedence

### ACT-PREC-001
When both a named parameter `after_cluster_time` and session setting `mongo_after_cluster_time` are set, the named parameter shall take precedence for that `mongo_scan` call.

### ACT-PREC-002
When no named parameter is provided but a session setting is set, the session setting shall be used as the `afterClusterTime` for `mongo_scan`.

### ACT-PREC-003
When neither named parameter nor session setting is set, the system shall not include `afterClusterTime` in the read concern.

## ATTACH Integration

### ACT-ATTACH-001
When a session-level `mongo_after_cluster_time` is set, queries through ATTACH (`SELECT * FROM mongo_test.users`) shall include the `afterClusterTime` read concern.

## Compatibility

### ACT-COMPAT-001
When connected to a standalone MongoDB server (no replica set), the system shall send the `afterClusterTime` read concern without error; MongoDB standalone silently ignores it.

### ACT-COMPAT-002
When built with `MONGOCXX_LEGACY=ON` (mongocxx 3.x), the `afterClusterTime` read concern shall function identically to the default build, as MongoDB 3.6+ supports this feature.

## Composition with Operation Time

### ACT-COMPOSE-001
The system shall support using `mongo_operation_time()` output directly as the `after_cluster_time` parameter value: `after_cluster_time := (SELECT mongo_operation_time())`.

### ACT-COMPOSE-002
The system shall support using the oplog `ts` field value (VARCHAR `seconds:increment` format) as the `after_cluster_time` parameter value.

## Documentation

### ACT-DOC-001
The README and extension settings description shall state that `afterClusterTime` provides causal consistency, NOT time travel — the read returns current data that reflects all operations up to the given timestamp.

### ACT-DOC-002
The README shall include examples showing the full workflow: capture `mongo_operation_time()`, pass it to a subsequent read via both the named parameter and SET mechanisms.
