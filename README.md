# MSSQL_VECTOR_SEARCH_BENCH
A high-performance Go-based benchmark tool for testing SQL Server vector search capabilities across distributed clusters.


## Overview

This tool (`main_runner.go`) is designed to benchmark vector similarity search performance on SQL Server using the DiskANN algorithm. It supports distributed testing across multiple nodes and provides detailed performance metrics including QPS (Queries Per Second).

## Prerequisites

- **Go**: Version 1.25.3 or higher
- **SQL Server**: With vector search capabilities (DiskANN)
- **SSH Access**: For distributed testing (requires `sshpass`)
- **Python 3**: For result aggregation in shell scripts
- **Dataset**: JSONL file containing vector data (default: `vectors_large.jsonl`)

## Building the Application

### 1. Install Dependencies

First, ensure you have the Microsoft SQL Server driver for Go:

```bash
# Install the go-mssqldb driver
go get github.com/microsoft/go-mssqldb

# Download all dependencies
go mod download

# Tidy up the go.mod file
go mod tidy
```

The main dependency is:
- **github.com/microsoft/go-mssqldb** - Microsoft SQL Server driver for Go

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
|-----------|---------|-------------|
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
Recall (top_n): 50
Output (topk):  10

🔌 Ramping up connections...
✅ All connections ready. GO!
   [  5s] QPS: 1234
   [ 10s] QPS: 1256
...
==================================================
Concurrency:   50
Total QPS:     1245.67
P50 Latency:   12.34 ms
P99 Latency:   45.67 ms
Errors:        0
==================================================
```

## Distributed Cluster Testing

The project includes four shell scripts for testing different cluster configurations.

**Note**: The provided scripts use **4 client VMs** as the default configuration, but you can easily **modify the scripts to use fewer or more clients** depending on your infrastructure and testing requirements. Simply add or remove VM entries in the script arrays.

### 1. Single Node Cluster (`run_1node_cluster.sh`)

Tests 4 client VMs against a single SQL Server node.

```bash
./run_1node_cluster.sh
```

**Configuration:**
- 4 Client VMs distributing load
- Concurrency levels: 10, 20, 30, 40, 50, 60, 70, 80, 90, 100
- Duration: 30 seconds per level
- Output: `./go_cluster_results_<timestamp>/`

### 2. Two Node Cluster (`run_2node_cluster.sh`)

Tests 4 clients against 2 SQL Server nodes (SQL5 and SQL6).

```bash
./run_2node_cluster.sh
```

**Configuration:**
- 2 Clients → SQL Node 5 (Table 5)
- 2 Clients → SQL Node 6 (Table 6)
- Concurrency levels: 10, 20, 30, 40, 50, 60, 70, 80, 90, 100
- Duration: 30 seconds per level
- Output: `./go_2node_verify_<timestamp>/`

### 3. Four Node Cluster (`run_4node_cluster.sh`)

Tests 4 clients against 4 SQL Server nodes with balanced distribution.

```bash
./run_4node_cluster.sh
```

**Configuration:**
- VM1 → SQL1 (Tables 1,4)
- VM2 → SQL2 (Tables 2,5,10)
- VM3 → SQL3 (Tables 7,8,3)
- VM4 → SQL4 (Tables 9,6)
- Concurrency levels: 10, 20, 30, 40, 50, 60, 70, 80, 90, 100
- Duration: 30 seconds per level
- Output: `./go_4node_results_<timestamp>/`

### 4. Eight Node Cluster (`run_8node_cluster.sh`)

Tests 4 clients driving 8 SQL Server nodes with optimized load distribution.

```bash
./run_8node_cluster.sh
```

**Configuration:**
- Client 1 → SQL1 (Table 1) & SQL5 (Table 5)
- Client 2 → SQL2 (Table 2) & SQL6 (Table 6) & SQL4 (Table 4)
- Client 3 → SQL3 (Table 3) & SQL7 (Tables 7,9)
- Client 4 → SQL8 (Tables 8,10)
- Concurrency levels: 10, 20, 30, 40, 50, 60, 70, 80, 90, 100
- Duration: 30 seconds per level
- Output: `./go_8node_results_<timestamp>/`

## Shell Script Requirements

Before running cluster tests, ensure:

1. **SSH Access**: Passwordless SSH or `sshpass` installed
2. **Binary Deployment**: `search_engine_v1` binary deployed to `/root/golang/` on all VMs
3. **Dataset**: `vectors_large.jsonl` available on all client VMs
4. **Network**: All VMs can reach SQL Server nodes
### Deploying to Remote VMs

```bash
# Build the binary
go build -o search_engine_v1 main_runner.go

# Deploy to all client machines
for ip in 10.21.22X.XX 10.21.22X.XX 10.21.22.XX 10.21.22X.XXX; do
  scp search_engine_v1 root@$ip:/root/golang/
  scp vectors_large.jsonl root@$ip:/root/golang/
done
```

## Output Files

Each test run creates a timestamped directory containing:

- **`summary.csv`**: Aggregated results (Concurrency, TotalQPS, AvgP50, AvgP95, AvgP99)
- **`vm_<IP>_level_<N>.log`**: Individual VM logs for each concurrency level
- **`vm_<IP>_target_<SQL>_level_<N>.log`**: Multi-node test logs (8-node config)

### Example Summary Output

```
Concurrency,TotalQPS,AvgP50,AvgP95,AvgP99
10,1234.56,0,0,12.34
20,2456.78,0,0,15.67
...
```


⚠️ **Issue**: The P50 and P99 latency metrics are currently experiencing printing issues to stdout in the benchmark output.

**Symptoms:**
- P50 and P99 values may not display correctly in the console output
- Shell scripts parsing these values may fail to extract metrics properly
- Summary CSV files may show `0` or missing values for P50/P99 columns

**Status**: Yet to code correctly



