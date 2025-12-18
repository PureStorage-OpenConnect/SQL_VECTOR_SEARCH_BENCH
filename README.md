# MSSQL_VECTOR_SEARCH_BENCH
A high-performance Go-based benchmark tool for testing SQL Server vector search capabilities across distributed clusters.

## Overview

This tool (`main_runner.go`) is designed to benchmark vector similarity search performance on SQL Server using the DiskANN algorithm. It supports distributed testing across multiple nodes and provides detailed performance metrics including QPS (Queries Per Second).

## Prerequisites

- **Go**: Version 1.25.3 or higher
- **SQL Server**: With vector search capabilities (DiskANN)
- **SSH Access**: For distributed testing (requires `sshpass`)
- **Python 3**: For result aggregation and dataset serialization
- **Dataset**: JSONL file containing vector data (default: `vectors_large.jsonl`)

## Dataset Preparation (Critical)

While the tool can function with synthetic data, **true realistic validation** requires using actual vector datasets (e.g., 10k to 20k vectors or more) to properly stress the storage subsystem.

We provide a Python utility to convert and serialize standard Parquet datasets into the JSONL format required by the benchmark tool.

### 1. Serialize Your Dataset
Use the provided `serialize_parquet.py` script to convert your vector data.
**Script Source:** [serialize_parquet.py](https://github.com/PureStorage-OpenConnect/SQL_VECTOR_SEARCH_BENCH/blob/main/serialize_parquet.py)

### 2. Configuration
Before running the script, open `serialize_parquet.py` and modify the input/output paths:

```python
# Open serialize_parquet.py and locate these lines:
parquet_file = "your_source_dataset.parquet"  # Change to your source file
jsonl_file = "vectors_large.jsonl"            # Output filename

```

### 3. Execution & Deployment

Run the script to generate the JSONL file:

```bash
python3 serialize_parquet.py

```

⚠️ **Requirement:** Ensure the generated `vectors_large.jsonl` is accessible to the load generator on **all client machines**.

```bash
# Example deployment to client nodes
for ip in 10.21.22X.XX 10.21.22X.XX; do
  scp vectors_large.jsonl root@$ip:/root/golang/
done

```

## Building the Application

### 1. Install Dependencies

First, ensure you have the Microsoft SQL Server driver for Go:

```bash
# Install the go-mssqldb driver
go get [github.com/microsoft/go-mssqldb](https://github.com/microsoft/go-mssqldb)

# Download all dependencies
go mod download
go mod tidy

```

### 2. Build the Binary

```bash
# Build for local execution
go build -o main_runner main_runner.go

# Build for distributed deployment (recommended name)
go build -o search_engine_v1 main_runner.go

```

### 3. Verify Build

```bash
./main_runner -h

```

## Configuration Parameters

| Parameter | Default | Description |
| --- | --- | --- |
| `-server` | `10.21.2XX.XX` | SQL Server IP address |
| `-user` | `sa` | SQL Server username |
| `-password` | `` | SQL Server password |
| `-db` | `MyDatabase` | Database name |
| `-duration` | `60` | Test duration in seconds |
| `-concurrency` | `50` | Number of concurrent workers |
| `-topk` | `10` | Number of rows to return (SELECT TOP) |
| `-top_n` | `50` | Candidates to scan (DiskANN top_n) |
| `-tables` | `1` | Comma-separated table numbers (e.g., "1,2,3") |
| `-dataset` | `/root/golang/vectors_large.jsonl` | Path to vector dataset |

## Running the Benchmark

### Single Node Test

```bash
./main_runner \
  -server 10.21.220.8 \
  -password '' \
  -tables '1,2,3' \
  -concurrency 50 \
  -duration 60 \
  -topk 10 \
  -top_n 50

```

### Understanding Output

The tool provides real-time monitoring and final statistics:

```
==================================================
   GO BENCHMARK HYPER - Optimized
==================================================
Target:       10.2X.2XX.XX
Concurrency:  50
...
==================================================
Concurrency:   50
Total QPS:     1245.67
P50 Latency:   12.34 ms
P99 Latency:   45.67 ms
Errors:        0
==================================================

```

## Distributed Cluster Testing (Automated Scripts)

The project includes four shell scripts for testing different cluster configurations.
**Note**: The scripts use **4 client VMs** by default. Modify the script arrays to add/remove clients.

### 1. Single Node Cluster (`run_1node_cluster.sh`)

Tests 4 client VMs against a single SQL Server node.

### 2. Two Node Cluster (`run_2node_cluster.sh`)

Tests 4 clients against 2 SQL Server nodes (SQL5 and SQL6).

### 3. Four Node Cluster (`run_4node_cluster.sh`)

Tests 4 clients against 4 SQL Server nodes with balanced distribution.

### 4. Eight Node Cluster (`run_8node_cluster.sh`)

Tests 4 clients driving 8 SQL Server nodes with optimized load distribution.

* **Client 1** → SQL1 (Table 1) & SQL5 (Table 5)
* **Client 2** → SQL2 (Table 2) & SQL6 (Table 6) & SQL4 (Table 4)
* **Client 3** → SQL3 (Table 3) & SQL7 (Tables 7,9)
* **Client 4** → SQL8 (Tables 8,10)

## Manual 8-Node Execution Guide (Precision Testing)

For precise control without shell scripts, use the following manual commands to reproduce the 8-node distributed topology. Run these simultaneously across your 4 Client VMs.

### 🛑 Client VM 1

**Target:** SQL Node 1 (Table 1) & SQL Node 5 (Table 5)

```bash
# Terminal 1
./search_engine_v1 -server 10.21.220.8  -tables "1" -concurrency 50 -duration 60 &

# Terminal 2
./search_engine_v1 -server 10.21.220.12 -tables "5" -concurrency 50 -duration 60 &

```

### 🛑 Client VM 2

**Target:** SQL Node 2 (Table 2), SQL Node 6 (Table 6), SQL Node 4 (Table 4)

```bash
./search_engine_v1 -server 10.21.220.9  -tables "2" -concurrency 50 -duration 60 &
./search_engine_v1 -server 10.21.220.13 -tables "6" -concurrency 50 -duration 60 &
./search_engine_v1 -server 10.21.220.11 -tables "4" -concurrency 50 -duration 60 &

```

### 🛑 Client VM 3

**Target:** SQL Node 3 (Table 3), SQL Node 7 (Tables 7, 9)

```bash
./search_engine_v1 -server 10.21.220.10 -tables "3" -concurrency 50 -duration 60 &
./search_engine_v1 -server 10.21.220.14 -tables "7" -concurrency 50 -duration 60 &
./search_engine_v1 -server 10.21.220.14 -tables "9" -concurrency 50 -duration 60 &

```

### 🛑 Client VM 4

**Target:** SQL Node 8 (Tables 8, 10)

```bash
./search_engine_v1 -server 10.21.220.15 -tables "8"  -concurrency 50 -duration 60 &
./search_engine_v1 -server 10.21.220.15 -tables "10" -concurrency 50 -duration 60 &

```

## Output Files

Each test run creates a timestamped directory containing:

* **`summary.csv`**: Aggregated results (Concurrency, TotalQPS, AvgP50, AvgP95, AvgP99)
* **`vm_<IP>_level_<N>.log`**: Individual VM logs.

## Known Issues

⚠️ **Latency Display Issue**: The P50 and P99 latency metrics are currently experiencing printing issues to stdout in the benchmark output.

* **Status**: Fix in progress.
* **Impact**: Shell scripts parsing these values may fail to extract metrics properly, and summary CSV files may show `0` for latency columns.

```

```
