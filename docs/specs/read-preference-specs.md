# EARS Specifications: Read Preference

## Named Parameter (mongo_scan)

### RP-PARAM-001
When `read_preference` named parameter is provided to `mongo_scan`, the system shall set the corresponding `mongocxx::read_preference` on the `find()` or `aggregate()` options.

### RP-PARAM-002
When `read_preference` is provided as a case-insensitive string, the system shall accept: `primary`, `primaryPreferred`, `primary_preferred`, `secondary`, `secondaryPreferred`, `secondary_preferred`, `nearest`.

### RP-PARAM-003
When `read_preference` is provided with an unrecognized value, the system shall raise an `InvalidInputException` listing the valid options.

### RP-PARAM-004
When `read_preference` is empty or NULL, the system shall not override the read preference (use connection string default or MongoDB default of `primary`).

## Session Setting

### RP-SET-001
The system shall register a `mongo_read_preference` extension option of type VARCHAR with session scope and empty default value.

### RP-SET-002
When `SET mongo_read_preference = <value>` is executed, the system shall accept the same values as the named parameter (case-insensitive, camelCase and snake_case).

### RP-SET-003
When `RESET mongo_read_preference` is executed, the system shall clear the session-level read preference so subsequent reads use the connection default.

### RP-SET-004
The `mongo_read_preference` setting shall be visible in `SELECT * FROM duckdb_settings() WHERE name LIKE 'mongo%'`.

## Precedence

### RP-PREC-001
When both a named parameter `read_preference` and session setting `mongo_read_preference` are set, the named parameter shall take precedence for that `mongo_scan` call.

### RP-PREC-002
When no named parameter is provided but a session setting is set, the session setting shall be used as the read preference for `mongo_scan`.

### RP-PREC-003
When neither named parameter nor session setting is set, the system shall not override the read preference (connection string or MongoDB default applies).

## ATTACH Integration

### RP-ATTACH-001
When a session-level `mongo_read_preference` is set, queries through ATTACH (`SELECT * FROM mongo_test.users`) shall use the specified read preference.

## Compatibility

### RP-COMPAT-001
When connected to a standalone MongoDB server, the system shall send the read preference without error; MongoDB standalone ignores it for `primary` and errors for `secondary`-only modes (the error should propagate to the user).

### RP-COMPAT-002
When built with `MONGOCXX_LEGACY=ON` (mongocxx 3.x), read preference shall function identically to the default build.

## Composition

### RP-COMPOSE-001
The system shall allow `read_preference` and `after_cluster_time` to be used together on the same `mongo_scan` call or within the same session, applying both independently.
