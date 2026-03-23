#!/bin/bash
# Script to generate TPC-H data and load it into MongoDB
# Similar to create-postgres-tables.sh but adapted for MongoDB

set -eo pipefail

DUCKDB_PATH=""
if test -f build/release/duckdb; then
  DUCKDB_PATH=./build/release/duckdb
elif test -f build/reldebug/duckdb; then
  DUCKDB_PATH=./build/reldebug/duckdb
elif test -f build/debug/duckdb; then
  DUCKDB_PATH=./build/debug/duckdb
elif command -v duckdb &>/dev/null; then
  DUCKDB_PATH=duckdb
else
  echo "Error: DuckDB binary not found."
  echo "Build the project first: make release"
  exit 1
fi

echo "Using DuckDB: $DUCKDB_PATH"

MONGO_HOST=${MONGO_HOST:-localhost}
MONGO_PORT=${MONGO_PORT:-27017}
MONGO_DB=${MONGO_DB:-tpch}
# Scale factor: 0.01 = ~10MB (quick test), 0.1 = ~100MB (dev), 1 = ~1GB (benchmark), 10 = ~10GB (production)
SCALE_FACTOR=${SCALE_FACTOR:-0.01}

echo "=== Generating TPC-H data (scale factor: $SCALE_FACTOR) ==="

# Create a temporary DuckDB database file to generate and export TPC-H data
TEMP_DB="/tmp/tpch_mongo_tmp/tpch_data.duckdb"
mkdir -p /tmp/tpch_mongo_tmp

# Run each step separately with -c for reliable error detection.
# DuckDB may exit 0 on SQL errors when reading from stdin/file, but -c propagates errors.
$DUCKDB_PATH $TEMP_DB -c "DROP SCHEMA IF EXISTS tpch CASCADE;" 2>/dev/null || true

$DUCKDB_PATH $TEMP_DB -c "LOAD tpch;" || {
    echo "Error: Failed to load tpch extension."
    echo "Rebuild DuckDB with tpch: make clean && make release"
    exit 1
}

$DUCKDB_PATH $TEMP_DB -c "CREATE SCHEMA IF NOT EXISTS tpch;" || {
    echo "Error: Failed to create tpch schema."
    exit 1
}

$DUCKDB_PATH $TEMP_DB -c "LOAD tpch; CALL dbgen(sf=$SCALE_FACTOR, schema='tpch');" || {
    echo "Error: Failed to generate TPC-H data with dbgen."
    exit 1
}

# Verify data was actually generated
REGION_COUNT=$($DUCKDB_PATH $TEMP_DB -csv -noheader -c "SELECT count(*) FROM tpch.region;" 2>&1) || {
    echo "Error: TPC-H schema exists but has no data."
    echo "DuckDB output: $REGION_COUNT"
    exit 1
}
echo "TPC-H data generated successfully ($REGION_COUNT regions)"

echo ""
echo "=== Loading TPC-H data into MongoDB ==="

# Check if mongosh is available
if ! command -v mongosh &> /dev/null; then
    echo "Error: mongosh is not installed. Please install MongoDB shell."
    echo "On macOS: brew install mongosh"
    exit 1
fi

# Drop and create database
mongosh "mongodb://$MONGO_HOST:$MONGO_PORT/$MONGO_DB" --eval "
db.dropDatabase();
print('Database $MONGO_DB dropped and will be recreated');
"

# Export tables to CSV format, then load into MongoDB
TPCH_TABLES=("region" "nation" "supplier" "customer" "part" "partsupp" "orders" "lineitem")

for table in "${TPCH_TABLES[@]}"; do
    echo "Loading $table..."
    
    # Export table to CSV using DuckDB, then load into MongoDB
    CSV_FILE="/tmp/tpch_mongo_tmp/${table}_export.csv"
    
    # Export table to CSV from the temporary database
    $DUCKDB_PATH $TEMP_DB -c "USE tpch; COPY (SELECT * FROM $table) TO '$CSV_FILE' (HEADER, DELIMITER '|');"
    
    if [ ! -f "$CSV_FILE" ]; then
        echo "Error: Failed to export $table to CSV"
        echo "Check that DuckDB ($DUCKDB_PATH) has the tpch extension and the dbgen step succeeded."
        exit 1
    fi
    
    # Load CSV into MongoDB using mongosh
    # For large files (like lineitem), process in chunks to avoid memory issues
    if [ "${table}" = "lineitem" ] && [ -f "$CSV_FILE" ]; then
        # Use Python for lineitem to handle large files better
        python3 << PYTHON_SCRIPT
import csv
import sys
from pymongo import MongoClient
from datetime import datetime
import re

client = MongoClient('mongodb://$MONGO_HOST:$MONGO_PORT/')
db = client['$MONGO_DB']
collection = db['${table}']

date_suffixes = ['date', 'Date', 'DATE']
def is_date_column(header):
    return any(header.lower().endswith(suffix.lower()) for suffix in date_suffixes)

def is_date_string(s):
    if not s or not isinstance(s, str):
        return False
    pattern = r'^\d{4}-\d{2}-\d{2}$'
    if not re.match(pattern, s):
        return False
    try:
        date = datetime.strptime(s, '%Y-%m-%d')
        return True
    except:
        return False

batch = []
batch_size = 50000
total = 0

with open('$CSV_FILE', 'r', encoding='utf-8') as f:
    reader = csv.reader(f, delimiter='|')
    headers = [h.strip() for h in next(reader)]
    
    for row in reader:
        if not row or len(row) == 0:
            continue
        doc = {}
        for idx, header in enumerate(headers):
            value = row[idx] if idx < len(row) else None
            if value is None or value == '':
                doc[header] = None
            else:
                trimmed = value.strip()
                # Strip quotes
                if len(trimmed) >= 2:
                    if trimmed.startswith('"') and trimmed.endswith('"'):
                        trimmed = trimmed[1:-1].replace('""', '"')
                    elif trimmed.startswith("'") and trimmed.endswith("'"):
                        trimmed = trimmed[1:-1]
                
                if trimmed == 'NULL' or trimmed == '':
                    doc[header] = None
                elif is_date_column(header) and is_date_string(trimmed):
                    doc[header] = datetime.strptime(trimmed, '%Y-%m-%d')
                else:
                    try:
                        if '.' in trimmed:
                            doc[header] = float(trimmed)
                        else:
                            doc[header] = int(trimmed)
                    except ValueError:
                        doc[header] = trimmed
        
        batch.append(doc)
        if len(batch) >= batch_size:
            collection.insert_many(batch)
            total += len(batch)
            print(f"Inserted batch: {len(batch)} documents (total: {total})", flush=True)
            batch = []
    
    if batch:
        collection.insert_many(batch)
        total += len(batch)
        print(f"Inserted final batch: {len(batch)} documents (total: {total})", flush=True)

print(f"Inserted {total} documents into ${table}", flush=True)
PYTHON_SCRIPT
    else
        # For smaller tables, use mongosh
        mongosh "mongodb://$MONGO_HOST:$MONGO_PORT/$MONGO_DB" --eval "
        const fs = require('fs');
        const csv = fs.readFileSync('$CSV_FILE', 'utf-8');
        const lines = csv.trim().split('\\n');
    
    if (lines.length < 2) {
        print(\"Warning: CSV file for ${table} is empty or has no data rows\");
        quit(0);
    }
    
    // Parse CSV header (first line)
    const headers = lines[0].split(\"|\").map(h => h.trim());
    
    // TPC-H date columns (suffixes that indicate dates)
    const dateSuffixes = [\"date\", \"Date\", \"DATE\"];
    const isDateColumn = (header) => {
        return dateSuffixes.some(suffix => header.toLowerCase().endsWith(suffix.toLowerCase()));
    };
    
    // Helper function to check if a string looks like a date (YYYY-MM-DD format)
    const isDateString = (str) => {
        if (!str || typeof str !== \"string\") return false;
        const datePattern = /^\\d{4}-\\d{2}-\\d{2}$/;
        if (!datePattern.test(str)) return false;
        // Try to parse it as a date
        const date = new Date(str);
        return !isNaN(date.getTime()) && date.toISOString().startsWith(str);
    };
    
    // Process in batches to avoid memory issues with large datasets
    const BATCH_SIZE = 50000;
    let totalInserted = 0;
    
    for (let batchStart = 1; batchStart < lines.length; batchStart += BATCH_SIZE) {
        const documents = [];
        const batchEnd = Math.min(batchStart + BATCH_SIZE, lines.length);
        
        for (let i = batchStart; i < batchEnd; i++) {
            if (!lines[i].trim()) continue;
            const values = lines[i].split('|');
            const doc = {};
            headers.forEach((header, idx) => {
                const value = values[idx];
                if (value === undefined || value === null) {
                    doc[header] = null;
                } else {
                    // Preserve whitespace to match TPC-H expected results
                    // Strip surrounding quotes if present (DuckDB exports strings with special characters quoted)
                    let trimmed = value;
                    if (trimmed.length >= 2) {
                        if (trimmed.startsWith(\"\\\"\") && trimmed.endsWith(\"\\\"\")) {
                            trimmed = trimmed.slice(1, -1);
                            // Handle escaped quotes (double quotes inside)
                            trimmed = trimmed.replace(/\"\"/g, \"\\\"\");
                        } else if (trimmed.startsWith(\"'\") && trimmed.endsWith(\"'\")) {
                            trimmed = trimmed.slice(1, -1);
                        }
                    }
                    
                    if (trimmed === \"NULL\" || trimmed === \"\") {
                        doc[header] = null;
                    } else if (isDateColumn(header) && isDateString(trimmed)) {
                        // Store dates as MongoDB Date objects for proper date comparisons
                        doc[header] = new Date(trimmed);
                    } else if (trimmed !== \"\" && !isNaN(trimmed) && trimmed !== \"NULL\") {
                        // Try to convert to number if it looks like a number
                        if (trimmed.includes(\".\")) {
                            doc[header] = parseFloat(trimmed);
                        } else {
                            doc[header] = parseInt(trimmed, 10);
                        }
                    } else {
                        doc[header] = trimmed;
                    }
                }
            });
            documents.push(doc);
        }
        
        if (documents.length > 0) {
            db.${table}.insertMany(documents);
            totalInserted += documents.length;
            print(\"Inserted batch: \" + documents.length + \" documents (total: \" + totalInserted + \")\");
        }
    }
    
    print(\"Inserted \" + totalInserted + \" documents into ${table}\");
    "
    fi
done

echo ""
echo "=== Creating indexes ==="

# Create indexes similar to what would be in Postgres
mongosh "mongodb://$MONGO_HOST:$MONGO_PORT/$MONGO_DB" --eval "
// Indexes for lineitem (most queried table)
db.lineitem.createIndex({l_orderkey: 1});
db.lineitem.createIndex({l_partkey: 1});
db.lineitem.createIndex({l_suppkey: 1});
db.lineitem.createIndex({l_shipdate: 1});
db.lineitem.createIndex({l_commitdate: 1});
db.lineitem.createIndex({l_receiptdate: 1});

// Indexes for orders
db.orders.createIndex({o_orderkey: 1});
db.orders.createIndex({o_custkey: 1});
db.orders.createIndex({o_orderdate: 1});
db.orders.createIndex({o_orderstatus: 1});

// Indexes for customer
db.customer.createIndex({c_custkey: 1});
db.customer.createIndex({c_nationkey: 1});

// Indexes for part
db.part.createIndex({p_partkey: 1});
db.part.createIndex({p_brand: 1});
db.part.createIndex({p_type: 1});

// Indexes for partsupp
db.partsupp.createIndex({ps_partkey: 1});
db.partsupp.createIndex({ps_suppkey: 1});

// Indexes for supplier
db.supplier.createIndex({s_suppkey: 1});
db.supplier.createIndex({s_nationkey: 1});

// Indexes for nation
db.nation.createIndex({n_nationkey: 1});
db.nation.createIndex({n_regionkey: 1});

// Indexes for region
db.region.createIndex({r_regionkey: 1});

print(\"Indexes created successfully\");
"

# Cleanup temporary files
rm -rf /tmp/tpch_mongo_tmp

echo ""
echo "=== TPC-H data loaded into MongoDB ==="
echo "Database: $MONGO_DB"
echo "Collections: ${TPCH_TABLES[*]}"
echo ""

# Export environment variables for tests
export MONGODB_TEST_DATABASE_AVAILABLE=1
export MONGO_TPCH_DATABASE="$MONGO_DB"

echo "Environment variables set:"
echo "  MONGODB_TEST_DATABASE_AVAILABLE=1"
echo "  MONGO_TPCH_DATABASE=$MONGO_DB"
echo ""
echo "Note: These variables are exported in the current shell session."
echo "To use in other shells, run:"
echo "  export MONGODB_TEST_DATABASE_AVAILABLE=1"
echo "  export MONGO_TPCH_DATABASE=$MONGO_DB"

