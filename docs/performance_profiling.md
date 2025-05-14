# Ingestor System - Performance Profiling Guide

This document describes the performance profiling system for the Ingestor System, including how to use it to identify bottlenecks and optimize performance.

## Overview

The performance profiling system provides tools to measure execution time and resource usage of key operations within the Ingestor System. It's designed to be minimally invasive and incur minimal overhead when not actively being used.

The primary components of the profiling system are:

1. **Core Profiler Module** (`src/modules/profiler.sh`): The central module that tracks execution times, resource usage, and manages benchmarks.

2. **Profiled Modules**: Modified versions of key modules that include profiling instrumentation:
   - `database_profiled.sh`: Database operations
   - `content_profiled.sh`: Content processing operations
   - `claude_profiled.sh`: Claude AI integration operations

3. **Ingestor with Profiling Wrapper** (`src/ingestor_with_profiling`): A wrapper around the main ingestor script that enables profiling and report generation.

4. **Profile Manager** (`scripts/profile_manager.sh`): A utility script to manage profiling settings, run benchmarks, and analyze results.

## Getting Started

### Enable Profiling

To enable profiling for the entire system:

```bash
./scripts/profile_manager.sh enable
```

This will enable profiling for all operations when using either the standard ingestor or the profiling wrapper.

### Run with Profiling

You can use the profiling wrapper to run operations with profiling enabled:

```bash
./src/ingestor_with_profiling --database research --file document.pdf
```

To generate a profiling report at the end of execution, add the `--profile-report` option:

```bash
./src/ingestor_with_profiling --database research --file document.pdf --profile-report
```

### Disable Profiling

To disable profiling for the entire system:

```bash
./scripts/profile_manager.sh disable
```

## Creating Benchmarks

Benchmarks help establish baseline performance metrics for various operations, allowing you to identify when performance degrades.

```bash
# Run all benchmarks
./scripts/profile_manager.sh benchmark all

# Run database benchmarks
./scripts/profile_manager.sh benchmark database

# Run content processing benchmarks
./scripts/profile_manager.sh benchmark content

# Run Claude AI benchmarks
./scripts/profile_manager.sh benchmark claude
```

## Analyzing Performance Data

### Generate Reports

You can generate a performance analysis report from any profiling log:

```bash
# Analyze the most recent log
./scripts/profile_manager.sh analyze

# Specify a log file
./scripts/profile_manager.sh analyze /path/to/profiling_log.log

# Specify output format (markdown, json, csv)
./scripts/profile_manager.sh analyze --format json
```

### Clean Old Logs

To clean up old profiling logs:

```bash
# Delete logs older than 30 days (default)
./scripts/profile_manager.sh clean

# Delete logs older than 7 days
./scripts/profile_manager.sh clean 7
```

## Understanding Profiling Reports

Profiling reports include:

1. **Summary Table**: A high-level view of all operations, their counts, and average execution times
2. **Operation Details**: Detailed statistics for each operation
3. **Optimization Opportunities**: Identification of slow operations that may benefit from optimization
4. **Benchmarks Comparison**: How current performance compares to established benchmarks

### Example Report

```markdown
# Ingestor System Performance Analysis
**Generated:** Mon May 13 14:30:45 PDT 2025

## Summary of Operations

| Operation | Count | Avg Duration (ms) | Min | Max |
|-----------|------:|------------------:|----:|----:|
| db_store_text | 15 | 123.45 | 95 | 210 |
| content_process | 8 | 567.89 | 450 | 820 |
| claude_analyze | 8 | 1234.56 | 980 | 1560 |

## Operation Details

### db_store_text
- **Count:** 15 executions
- **Average Duration:** 123.45 ms
- **Total Duration:** 1851.75 ms
- **Range:** 95 - 210 ms

[additional operation details...]

## Optimization Opportunities

Operations with highest average execution time:

1. **claude_analyze**: 1234.56 ms average (8 executions)
2. **content_process**: 567.89 ms average (8 executions)
3. **db_store_text**: 123.45 ms average (15 executions)
```

## Extending the Profiling System

### Adding Profiling to New Modules

1. Create a profiled version of your module (e.g., `your_module_profiled.sh`)
2. Import both your original module and the profiler
3. Create profiled versions of key functions
4. Add enable/disable functions
5. Update the profile manager to include your module in benchmarks

### Creating Custom Benchmarks

Create a custom benchmark script that focuses on specific operations:

```bash
# Create a custom benchmark file
touch my_custom_benchmark.sh

# Run custom benchmark
./scripts/profile_manager.sh benchmark custom my_custom_benchmark.sh
```

## Best Practices

1. **Selective Profiling**: Only enable profiling when needed to minimize overhead
2. **Regular Benchmarking**: Run benchmarks after significant changes to detect regressions
3. **Targeted Optimization**: Focus on optimizing the slowest and most frequently used operations
4. **Clean Old Logs**: Regularly clean up old profiling logs to save disk space
5. **Compare to Baselines**: Always compare current performance to established benchmarks

## Implementation Details

### Profiling Data Storage

Profiling data is stored in:

- Logs: `~/.ingestor/logs/profiling/`
- Benchmarks: `~/.ingestor/benchmarks/`
- Reports: Generated in the same directory as logs

### Overhead Considerations

The profiling system is designed to have minimal impact when not in use:

- Profiling can be completely disabled when not needed
- When profiling is enabled, the overhead per operation is typically <1ms
- Benchmark data is stored in a compact JSON format

## Troubleshooting

### Common Issues

1. **Missing Profiling Logs**: Ensure you've enabled profiling and have write permissions to the log directory.
2. **High Overhead**: If profiling causes noticeable slowdowns, try profiling specific modules rather than the entire system.
3. **Incorrect Benchmark Results**: Make sure you're running benchmarks in a consistent environment with minimal background activity.

## Advanced Usage

### Custom Metrics

In addition to execution time, you can track custom metrics:

```bash
# Start profiling with custom metrics
start_profile "my_operation"
# ...perform operation...
# Custom metrics
local my_metric="my_value"
# End profiling with custom info
end_profile "my_operation" "custom:${my_metric}"
```

### Programmatic Access to Profiling Data

You can access profiling data programmatically from logs:

```bash
# Extract average execution time for an operation
average_time=$(grep "db_store_text" ~/.ingestor/logs/profiling/latest.log | 
               awk -F, '{sum+=$2; count++} END {print sum/count}')
```

## Conclusion

The performance profiling system provides comprehensive tools for monitoring, analyzing, and optimizing the performance of the Ingestor System. By regularly benchmarking and profiling your operations, you can ensure optimal performance and identify bottlenecks before they impact users.