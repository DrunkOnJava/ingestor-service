# Structured Logging System

The Ingestor System includes a comprehensive structured logging module that supports both traditional human-readable logs and structured JSON logging. This documentation covers how to use the logging system in both Bash scripts and Node.js components.

## Features

- Different log levels (DEBUG, INFO, WARNING/WARN, ERROR)
- ISO 8601 compliant timestamps
- JSON structured output format
- Context information (module, function, line number)
- Configurable log destination (file, stdout, or both)
- Toggle between human-readable and JSON formats
- Performance metrics tracking
- Event logging
- Exception/error tracking with stack traces
- Child loggers with predefined context

## Bash Script Usage

### Basic Usage

```bash
# Source the structured logging module
source "$(dirname "${BASH_SOURCE[0]}")/../modules/structured_logging.sh"

# Initialize logging
init_structured_logging

# Configure logging (optional)
# Args: format (human|json), destination (file|stdout|both), context_enabled (true|false)
configure_logging "json" "both" "true"

# Log messages at different levels
log_structured_debug "This is a debug message"
log_structured_info "This is an info message"
log_structured_warning "This is a warning message"
log_structured_error "This is an error message"

# Log with additional fields (only visible in JSON format)
log_structured_info "User logged in" "$(build_log_fields "user" "\"john.doe\"" "ip" "\"192.168.1.1\"")"

# Log metrics
log_metric "database_query" "150" "ms"

# Log events
log_event "user_login" "info" "{\"user\":\"john.doe\",\"ip\":\"192.168.1.1\"}"

# Log exceptions with stack traces
log_structured_exception "Failed to connect to database" "31" "DatabaseError"
```

### Environment Variables

The following environment variables can be used to configure logging:

- `LOG_LEVEL`: Sets the minimum log level (debug, info, warning, error)
- `LOG_FORMAT`: Sets the output format (human, json)
- `LOG_DESTINATION`: Sets where logs are sent (file, stdout, both)
- `LOG_CONTEXT_ENABLED`: Enables or disables context information (true, false)
- `LOG_DIR`: Directory where log files are stored

## Node.js Usage

### Basic Usage

```javascript
// Import the logger
const { logger, StructuredLogger } = require('../mcp/logger');

// Basic logging
logger.debug('This is a debug message');
logger.info('This is an info message');
logger.warn('This is a warning message');
logger.error('This is an error message', new Error('Something went wrong'));

// Log with additional fields
logger.info('User logged in', { user: 'john.doe', ip: '192.168.1.1' });

// Log metrics
logger.metric('database_query', 150, 'ms');

// Log events
logger.event('user_login', 'info', { user: 'john.doe', ip: '192.168.1.1' });

// Configure logger
logger.configure({
  level: 'debug',
  format: 'json',
  destination: 'both',
  contextEnabled: true
});

// Create a child logger with additional context
const dbLogger = logger.child({ module: 'database', component: 'query-executor' });
dbLogger.info('Executing query'); // Context will be included automatically
```

### Creating a Custom Logger

```javascript
const { StructuredLogger } = require('../mcp/logger');

// Create a custom logger instance
const customLogger = new StructuredLogger({
  level: 'debug',
  format: 'json',
  destination: 'file',
  contextEnabled: true,
  directory: '/custom/log/path',
  filename: 'custom-service.log'
});

customLogger.info('Custom logger initialized');
```

## Log Formats

### Human-Readable Format

Human-readable logs follow this format:

```
[2025-05-13 16:45:21] [INFO] [module:function:line] Message
```

When output to terminal, log levels are color-coded for better visibility.

### JSON Format

JSON logs follow this structure:

```json
{
  "timestamp": "2025-05-13T16:45:21.123Z",
  "level": "info",
  "message": "User logged in",
  "context": {
    "module": "auth",
    "function": "loginUser",
    "line": 42
  },
  "user": "john.doe",
  "ip": "192.168.1.1"
}
```

## Performance Impact

The structured logging system is designed to have minimal performance impact:

- When logging at a level that won't be output (e.g., debug logs when level is set to info), the performance overhead is negligible
- JSON formatting only occurs for logs that will actually be output
- File writes are buffered and performed asynchronously in Node.js

## Best Practices

1. **Choose the right log level**:
   - DEBUG: Detailed information for debugging
   - INFO: General information about application progress
   - WARNING: Potential issues that don't prevent normal operation
   - ERROR: Errors that prevent normal operation

2. **Structure your log messages**:
   - Keep messages clear and concise
   - Put variable data in fields, not in the message
   - Use metric and event logging for structured data

3. **Include context**:
   - Use additional fields to provide context
   - For important flows, create child loggers with context

4. **Configure appropriately**:
   - Use human-readable format for development
   - Use JSON format for production and log aggregation
   - Set log level to INFO in production

5. **Handle sensitive information**:
   - Never log passwords, tokens, or other sensitive information
   - Mask sensitive data before logging

## Log Analysis

The structured logging system integrates with common log analysis tools:

- **JSON logs** can be parsed by tools like Elasticsearch, Logstash, Kibana (ELK stack)
- **Grep and parse** logs using the provided utility functions:
  ```bash
  # Bash scripts
  grep_logs "database error" # Search logs for pattern
  parse_json_logs "user" "john.doe" # Extract JSON logs with specific field value
  ```

## Integration with Error Handling

The structured logging system integrates with the error handling module:

```bash
# In Bash scripts
handle_error() {
  local line_number="$1"
  local error_code="${2:-1}"
  local error_source="${BASH_SOURCE[1]:-unknown}"
  
  log_structured_exception "Error at line $line_number" "$error_code" "RuntimeError"
}

# In Node.js
try {
  // Some code that might throw
} catch (error) {
  logger.error('Operation failed', error, { operation: 'dataSync' });
}
```