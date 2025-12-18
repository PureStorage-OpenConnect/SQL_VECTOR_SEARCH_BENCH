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
