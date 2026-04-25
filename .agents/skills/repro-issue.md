# Investigate a GitHub Issue

Reproduce a GitHub issue, determine root cause, and verify a fix.

## Steps

### 1. Fetch and understand the issue

```bash
gh issue view <number> --repo stephaniewang526/duckdb-mongo
```

Identify: what the user expects, what actually happens, their data shape, and the error message.

### 2. Locate the relevant code

Use the symptom to find where to start reading:

| Symptom | Start here |
|---|---|
| Column not found / missing fields | `CollectFieldPaths()` in `mongo_schema_inference.cpp` |
| Wrong data type / type mismatch | `InferTypeFromBSONElement()` in `mongo_schema_inference_internal.hpp`, `ResolveTypeConflict()` |
| Wrong values returned | `FlattenDocument()` in `mongo_schema_inference.cpp` |
| Filter not working / wrong results | `mongo_filter_pushdown.cpp`, `mongo_expr_pushdown.cpp` |
| ATTACH / connection errors | `mongo_storage_extension.cpp`, `mongo_catalog.cpp` |
| Secrets / auth issues | `mongo_secrets.cpp` |
| Performance / too much data fetched | `mongo_optimizer.cpp`, `BuildMongoProjection()` in `mongo_table_function.cpp` |

Read the relevant source files before proposing changes.

### 3. Create minimal test data

Add a small collection (2-3 documents) to `test/create-mongo-tables.sh` that reproduces the issue. Comment with the issue number.

### 4. Write a failing test

Add to the most relevant existing test file in `test/sql/` — don't create a new file unless necessary. Use format-independent assertions (`LIKE`, `IS NOT NULL`, `COUNT(*)`) rather than exact JSON strings.

### 5. Implement the fix

Make the minimal change. Trace the full code path — a fix in one layer may need a corresponding change in another. Check whether existing tests need updating.

### 6. Verify

Rebuild and run the new test (should pass), then all tests (should not regress). See `.agents/skills/test.md` for how to build and run tests.

### 7. Summarize

Report: Is it a bug? Root cause, fix, test coverage, and risk of affecting existing functionality.
