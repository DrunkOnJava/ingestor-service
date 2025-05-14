/**
 * Structured logging module for Ingestor System MCP Server
 * 
 * Provides consistent logging with support for:
 * - Different log levels (DEBUG, INFO, WARN, ERROR)
 * - Timestamps in ISO 8601 format
 * - JSON structured output format
 * - Context information (module name, function name)
 * - Configurable log destination (file, stdout)
 * - Option to toggle between human-readable and JSON format
 */

const fs = require('fs');
const path = require('path');
const os = require('os');

// Default configuration
const DEFAULT_CONFIG = {
  level: 'info',
  format: 'human', // 'human' or 'json'
  destination: 'both', // 'file', 'stdout', or 'both'
  contextEnabled: true,
  directory: path.join(os.homedir(), '.ingestor', 'logs'),
  filename: `ingestor_structured_${new Date().toISOString().split('T')[0]}.log`
};

// Map log levels to numeric values for comparison
const LOG_LEVELS = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3
};

class StructuredLogger {
  constructor(config = {}) {
    // Merge default config with provided config
    this.config = { ...DEFAULT_CONFIG, ...config };
    
    // Ensure log directory exists
    if (!fs.existsSync(this.config.directory)) {
      fs.mkdirSync(this.config.directory, { recursive: true });
    }
    
    // Set log file path
    this.logFilePath = path.join(this.config.directory, this.config.filename);
    
    // Log initialization
    this.debug(`Logger initialized with level: ${this.config.level}, format: ${this.config.format}`);
    
    // Log system info at startup for troubleshooting
    if (this.config.format === 'json') {
      const systemInfo = this.formatSystemInfoJson();
      this.writeToFile(systemInfo);
    }
  }
  
  /**
   * Get basic system information as JSON
   */
  formatSystemInfoJson() {
    const timestamp = new Date().toISOString();
    const hostname = os.hostname();
    const platform = os.platform();
    const release = os.release();
    const pid = process.pid;
    
    return JSON.stringify({
      timestamp,
      level: 'info',
      message: 'Logging initialized',
      context: {
        system: {
          hostname,
          platform,
          release,
          pid,
          nodeVersion: process.version
        }
      }
    });
  }
  
  /**
   * Write log entry to file
   */
  writeToFile(message) {
    if (this.config.destination === 'file' || this.config.destination === 'both') {
      fs.appendFileSync(this.logFilePath, message + '\n');
    }
  }
  
  /**
   * Format log entry as JSON
   */
  formatJsonLog(level, message, context = {}, additionalFields = {}) {
    const timestamp = new Date().toISOString();
    
    // Determine calling module and function
    let callerInfo = {};
    if (this.config.contextEnabled && context) {
      callerInfo = {
        module: context.module || 'unknown',
        function: context.function || 'unknown'
      };
      
      if (context.line) {
        callerInfo.line = context.line;
      }
    }
    
    // Create log object
    const logObject = {
      timestamp,
      level,
      message,
      context: {
        ...callerInfo
      },
      ...additionalFields
    };
    
    return JSON.stringify(logObject);
  }
  
  /**
   * Format log entry as human-readable text
   */
  formatHumanLog(level, message, context = {}) {
    const timestamp = new Date().toLocaleString();
    const levelUppercase = level.toUpperCase();
    
    if (this.config.contextEnabled && context && (context.module || context.function)) {
      const ctxString = `${context.module || 'unknown'}:${context.function || 'unknown'}${context.line ? ':' + context.line : ''}`;
      return `[${timestamp}] [${levelUppercase}] [${ctxString}] ${message}`;
    } else {
      return `[${timestamp}] [${levelUppercase}] ${message}`;
    }
  }
  
  /**
   * Internal log function
   */
  log(level, message, context = {}, additionalFields = {}) {
    // Only log if level is high enough
    const levelNum = LOG_LEVELS[level];
    const currentLevelNum = LOG_LEVELS[this.config.level];
    
    if (levelNum < currentLevelNum) {
      return;
    }
    
    let formattedLog;
    if (this.config.format === 'json') {
      formattedLog = this.formatJsonLog(level, message, context, additionalFields);
    } else {
      formattedLog = this.formatHumanLog(level, message, context);
    }
    
    // Output based on destination configuration
    this.writeToFile(formattedLog);
    
    if (this.config.destination === 'stdout' || this.config.destination === 'both') {
      // Format for console output with colors if human format
      if (this.config.format === 'human') {
        switch (level) {
          case 'debug':
            console.log('\x1b[36m[DEBUG]\x1b[0m', message);
            break;
          case 'info':
            console.log('\x1b[32m[INFO]\x1b[0m', message);
            break;
          case 'warn':
            console.warn('\x1b[33m[WARN]\x1b[0m', message);
            break;
          case 'error':
            console.error('\x1b[31m[ERROR]\x1b[0m', message);
            break;
          default:
            console.log(`[${level.toUpperCase()}]`, message);
        }
      } else {
        console.log(formattedLog);
      }
    }
  }
  
  /**
   * Get calling context information
   */
  getCallerInfo() {
    const stackTrace = new Error().stack || '';
    const stackLines = stackTrace.split('\n').slice(3); // Skip Error, getCallerInfo, and the log method
    
    if (stackLines.length === 0) {
      return {};
    }
    
    const callerLine = stackLines[0];
    
    // Try to extract filename and line number from the stack trace
    const match = callerLine.match(/at (.*) \((.*):(\d+):(\d+)\)/) || 
                 callerLine.match(/at (.*):(\d+):(\d+)/);
    
    if (!match) {
      return {};
    }
    
    if (match.length === 5) {
      // Format: "at functionName (filename:line:column)"
      return {
        function: match[1],
        module: path.basename(match[2]),
        line: parseInt(match[3], 10)
      };
    } else {
      // Format: "at filename:line:column"
      return {
        module: path.basename(match[1]),
        line: parseInt(match[2], 10)
      };
    }
  }
  
  /**
   * Log a debug message
   */
  debug(message, additionalFields = {}) {
    this.log('debug', message, this.getCallerInfo(), additionalFields);
  }
  
  /**
   * Log an info message
   */
  info(message, additionalFields = {}) {
    this.log('info', message, this.getCallerInfo(), additionalFields);
  }
  
  /**
   * Log a warning message
   */
  warn(message, additionalFields = {}) {
    this.log('warn', message, this.getCallerInfo(), additionalFields);
  }
  
  /**
   * Log an error message
   */
  error(message, error, additionalFields = {}) {
    const context = this.getCallerInfo();
    
    // Add error details if available
    let errorFields = { ...additionalFields };
    
    if (error) {
      // Format stack trace for JSON output
      const stackFrames = error.stack ? 
        error.stack.split('\n').slice(1).map(line => line.trim()) : [];
      
      errorFields.exception = {
        message: error.message || String(error),
        name: error.name || 'Error',
        stack: stackFrames,
        code: error.code || undefined
      };
    }
    
    this.log('error', message, context, errorFields);
  }
  
  /**
   * Log a metric for performance tracking
   */
  metric(name, value, unit = 'ms', additionalFields = {}) {
    const metricFields = {
      metric: {
        name,
        value,
        unit,
        timestamp: new Date().toISOString()
      },
      ...additionalFields
    };
    
    this.info(`Metric: ${name}=${value}${unit}`, metricFields);
  }
  
  /**
   * Log an event for important system events
   */
  event(eventName, severity = 'info', details = {}, additionalFields = {}) {
    const eventFields = {
      event: {
        name: eventName,
        severity,
        details,
        timestamp: new Date().toISOString()
      },
      ...additionalFields
    };
    
    this.info(`Event: ${eventName}`, eventFields);
  }
  
  /**
   * Configure logger settings
   */
  configure(config = {}) {
    // Update configuration
    this.config = { ...this.config, ...config };
    
    // Validate level
    if (!LOG_LEVELS.hasOwnProperty(this.config.level)) {
      console.warn(`Invalid log level: ${this.config.level}. Using default: info`);
      this.config.level = 'info';
    }
    
    // Validate format
    if (this.config.format !== 'human' && this.config.format !== 'json') {
      console.warn(`Invalid log format: ${this.config.format}. Using default: human`);
      this.config.format = 'human';
    }
    
    // Validate destination
    if (this.config.destination !== 'file' && this.config.destination !== 'stdout' && this.config.destination !== 'both') {
      console.warn(`Invalid log destination: ${this.config.destination}. Using default: both`);
      this.config.destination = 'both';
    }
    
    this.info(`Logger reconfigured with level: ${this.config.level}, format: ${this.config.format}, destination: ${this.config.destination}`);
    
    // Update log file path if filename or directory changed
    this.logFilePath = path.join(this.config.directory, this.config.filename);
  }
  
  /**
   * Create a child logger with added context
   */
  child(context) {
    const childLogger = Object.create(this);
    
    // Wrapper methods that add the context
    const wrapMethod = (method) => {
      return function(message, ...args) {
        const callerInfo = this.getCallerInfo();
        const combinedContext = { ...context, ...callerInfo };
        return this.log(method, message, combinedContext, ...(args || []));
      };
    };
    
    // Override logging methods to include context
    childLogger.debug = wrapMethod('debug');
    childLogger.info = wrapMethod('info');
    childLogger.warn = wrapMethod('warn');
    childLogger.error = wrapMethod('error');
    
    return childLogger;
  }
}

// Create and export default logger instance
const defaultLogger = new StructuredLogger();

module.exports = {
  logger: defaultLogger,
  StructuredLogger,
  LOG_LEVELS
};