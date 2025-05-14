# Ingestor System Performance Profiling

This README provides a quick overview of the performance profiling system implemented for the Ingestor System project.

## Components

The profiling system consists of the following components:

1. **Core Profiling Module**: `src/modules/profiler.sh`
   - Measures execution time of functions and operations
   - Tracks memory usage and CPU utilization
   - Maintains benchmarks for performance comparison
   - Generates performance reports

2. **Profiled Module Wrappers**:
   - `src/modules/database_profiled.sh` - Profiles database operations
   - `src/modules/content_profiled.sh` - Profiles content processing operations
   - `src/modules/claude_profiled.sh` - Profiles Claude AI integration operations

3. **Profiling Wrapper Script**: `src/ingestor_with_profiling`
   - Wraps the main ingestor script with profiling capabilities
   - Can generate reports at the end of execution
   - Minimally invasive to normal operation

4. **Profile Management Tool**: `scripts/profile_manager.sh`
   - Enable/disable system-wide profiling
   - Run benchmarks for different operations
   - Analyze profiling logs and generate reports
   - Clean up old profiling data

5. **Documentation**: `docs/performance_profiling.md`
   - Comprehensive documentation on using the profiling system
   - Best practices for performance optimization
   - Extending the profiling system to new modules

## Quick Start

### Enable Profiling

```bash
./scripts/profile_manager.sh enable
```

### Run with Profiling

```bash
./src/ingestor_with_profiling --database research --file document.pdf --profile-report
```

### Run Benchmarks

```bash
./scripts/profile_manager.sh benchmark all
```

### Analyze Performance

```bash
./scripts/profile_manager.sh analyze
```

### Disable Profiling

```bash
./scripts/profile_manager.sh disable
```

## Key Features

- **Minimally Invasive**: Minimal performance impact when not in use
- **Comprehensive Metrics**: Tracks execution time, memory usage, and CPU utilization
- **Detailed Reports**: Generates markdown reports with optimization recommendations
- **Benchmarking**: Establishes performance baselines for comparison
- **Extensible**: Easy to add profiling to new modules

## Implementation Details

- **Storage Location**: `~/.ingestor/logs/profiling/` and `~/.ingestor/benchmarks/`
- **Report Format**: Markdown by default, with JSON and CSV options
- **Benchmarks**: Stored as JSON for easy loading and comparison
- **Overhead**: Typically <1ms per operation when profiling is enabled

## Key Monitored Operations

1. **Database Operations**:
   - Database initialization
   - Data storage operations
   - Queries and transactions
   - Backup and maintenance operations

2. **Content Processing**:
   - Content type detection
   - Content chunking
   - Processing various file types (text, PDFs, images, videos, code)

3. **Claude AI Integration**:
   - API request/response time
   - Analysis operations
   - Batch processing
   - Embedding generation

## Next Steps

For more detailed information, see the full documentation in `docs/performance_profiling.md`.