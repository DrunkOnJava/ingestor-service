/**
 * Logger class
 * Provides structured logging functionality for the ingestor system
 */

/**
 * Log levels for the Logger
 */
export enum LogLevel {
  DEBUG = 'debug',
  INFO = 'info',
  WARNING = 'warning',
  ERROR = 'error'
}

/**
 * Configuration options for the Logger
 */
export interface LoggerConfig {
  /** Minimum log level to output */
  level: LogLevel;
  /** Directory to write log files to */
  logDir?: string;
  /** Whether to output logs to console */
  console?: boolean;
  /** Whether to include timestamps in log messages */
  timestamps?: boolean;
  /** Whether to include structured metadata in log messages */
  structured?: boolean;
}

/**
 * Logger implementation for consistent logging across the application
 */
export class Logger {
  private config: LoggerConfig;
  private modulePrefix: string;
  
  /**
   * Creates a new Logger instance
   * @param modulePrefix Prefix to add to log messages to identify the module
   * @param config Configuration options
   */
  constructor(
    modulePrefix: string, 
    config: LoggerConfig = { 
      level: LogLevel.INFO,
      console: true,
      timestamps: true,
      structured: false
    }
  ) {
    this.modulePrefix = modulePrefix;
    this.config = config;
  }
  
  /**
   * Log a debug message
   * @param message Message to log
   * @param context Optional context information
   * @param method Optional method name
   */
  public debug(message: string, context?: string, method?: string): void {
    this.log(LogLevel.DEBUG, message, context, method);
  }
  
  /**
   * Log an info message
   * @param message Message to log
   * @param context Optional context information
   * @param method Optional method name
   */
  public info(message: string, context?: string, method?: string): void {
    this.log(LogLevel.INFO, message, context, method);
  }
  
  /**
   * Log a warning message
   * @param message Message to log
   * @param context Optional context information
   * @param method Optional method name
   */
  public warning(message: string, context?: string, method?: string): void {
    this.log(LogLevel.WARNING, message, context, method);
  }
  
  /**
   * Log an error message
   * @param message Message to log
   * @param context Optional context information
   * @param method Optional method name
   */
  public error(message: string, context?: string, method?: string): void {
    this.log(LogLevel.ERROR, message, context, method);
  }
  
  /**
   * Internal logging method
   * @param level Log level
   * @param message Message to log
   * @param context Optional context information
   * @param method Optional method name
   * @private
   */
  private log(level: LogLevel, message: string, context?: string, method?: string): void {
    // Don't log if level is below configured minimum
    if (!this.shouldLog(level)) {
      return;
    }
    
    const timestamp = this.config.timestamps ? new Date().toISOString() : '';
    const formattedContext = context ? `[${context}]` : '';
    const formattedMethod = method ? `[${method}]` : '';
    const modulePrefix = this.modulePrefix ? `[${this.modulePrefix}]` : '';
    
    let logMessage = '';
    
    if (this.config.structured) {
      // Structured JSON format
      const logData = {
        timestamp,
        level,
        module: this.modulePrefix,
        context,
        method,
        message
      };
      logMessage = JSON.stringify(logData);
    } else {
      // Simple format
      logMessage = [
        timestamp,
        `[${level.toUpperCase()}]`,
        modulePrefix,
        formattedContext,
        formattedMethod,
        message
      ].filter(Boolean).join(' ');
    }
    
    // Output to console if enabled
    if (this.config.console) {
      switch (level) {
        case LogLevel.ERROR:
          console.error(logMessage);
          break;
        case LogLevel.WARNING:
          console.warn(logMessage);
          break;
        case LogLevel.INFO:
          console.info(logMessage);
          break;
        case LogLevel.DEBUG:
          console.debug(logMessage);
          break;
      }
    }
    
    // File logging would be implemented here if needed
    // For simplicity, we're just doing console logging for now
  }
  
  /**
   * Check if a log level should be logged
   * @param level Log level to check
   * @returns True if the level should be logged
   * @private
   */
  private shouldLog(level: LogLevel): boolean {
    const levels = [LogLevel.DEBUG, LogLevel.INFO, LogLevel.WARNING, LogLevel.ERROR];
    const configIndex = levels.indexOf(this.config.level);
    const messageIndex = levels.indexOf(level);
    
    // Log if message level is equal to or higher than config level
    return messageIndex >= configIndex;
  }
  
  /**
   * Create a child logger with the same configuration but a different prefix
   * @param childPrefix Prefix for the child logger
   * @returns New Logger instance
   */
  public createChildLogger(childPrefix: string): Logger {
    return new Logger(`${this.modulePrefix}.${childPrefix}`, this.config);
  }
  
  /**
   * Set the logger configuration
   * @param config New configuration
   */
  public setConfig(config: Partial<LoggerConfig>): void {
    this.config = { ...this.config, ...config };
  }
  
  /**
   * Create a default logger instance
   * @param moduleName Name of the module
   * @returns Logger instance
   */
  public static createDefault(moduleName: string): Logger {
    const logLevel = (process.env.LOG_LEVEL as LogLevel) || LogLevel.INFO;
    return new Logger(moduleName, {
      level: logLevel,
      console: true,
      timestamps: true,
      structured: false
    });
  }
}