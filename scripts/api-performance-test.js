/**
 * API Performance Test Script
 * 
 * This script runs performance tests against the ingestor system API
 * using Node.js and the autocannon library for load testing.
 * 
 * Usage:
 *   node api-performance-test.js [options]
 * 
 * Options:
 *   --endpoint=<endpoint>  Specific endpoint to test (default: all endpoints)
 *   --duration=<seconds>   Test duration in seconds (default: 10)
 *   --connections=<num>    Number of concurrent connections (default: 10)
 *   --report=<path>        Path to save report (default: ./performance-report.json)
 */

import autocannon from 'autocannon';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

// Get current file directory
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Default options
const DEFAULT_OPTIONS = {
  endpoint: 'all',
  duration: 10,
  connections: 10,
  report: path.join(__dirname, '..', 'performance-report.json')
};

// Parse command line arguments
const parseArgs = () => {
  const args = process.argv.slice(2);
  const options = { ...DEFAULT_OPTIONS };
  
  args.forEach(arg => {
    if (arg.startsWith('--endpoint=')) {
      options.endpoint = arg.replace('--endpoint=', '');
    } else if (arg.startsWith('--duration=')) {
      options.duration = parseInt(arg.replace('--duration=', ''), 10);
    } else if (arg.startsWith('--connections=')) {
      options.connections = parseInt(arg.replace('--connections=', ''), 10);
    } else if (arg.startsWith('--report=')) {
      options.report = arg.replace('--report=', '');
    }
  });
  
  return options;
};

// API configuration
const API_CONFIG = {
  baseUrl: 'http://localhost:3000/api/v1',
  endpoints: {
    health: {
      method: 'GET',
      path: '/system/health',
      description: 'Health check endpoint'
    },
    info: {
      method: 'GET',
      path: '/system/info',
      description: 'System information endpoint'
    },
    databaseList: {
      method: 'GET',
      path: '/database/list',
      description: 'List databases endpoint'
    },
    entities: {
      method: 'GET',
      path: '/entities',
      description: 'List entities endpoint'
    },
    content: {
      method: 'GET',
      path: '/content',
      description: 'List content endpoint'
    }
  },
  // Add additional endpoints for POST tests with sample payloads
  postEndpoints: {
    login: {
      method: 'POST',
      path: '/auth/login',
      description: 'User login endpoint',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        username: 'testuser',
        password: 'Test1234!'
      })
    },
    processContent: {
      method: 'POST',
      path: '/processing/analyze',
      description: 'Process content endpoint',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        content: 'This is test content for performance testing.',
        contentType: 'text',
        options: {
          extractEntities: true
        }
      })
    }
  }
};

// Run performance test for a specific endpoint
const runTest = async (endpoint, options) => {
  const endpointConfig = { ...API_CONFIG.endpoints[endpoint] };
  const url = API_CONFIG.baseUrl + endpointConfig.path;
  
  console.log(`Running performance test for ${endpointConfig.description}...`);
  console.log(`URL: ${url}`);
  console.log(`Method: ${endpointConfig.method}`);
  console.log(`Duration: ${options.duration} seconds`);
  console.log(`Connections: ${options.connections}`);
  console.log('---------------------------------------------------');
  
  const testConfig = {
    url,
    method: endpointConfig.method,
    duration: options.duration,
    connections: options.connections,
    headers: endpointConfig.headers || {},
    body: endpointConfig.body || null,
    excludeErrorStats: false
  };
  
  // Run autocannon test
  const results = await autocannon(testConfig);
  
  return {
    endpoint,
    config: endpointConfig,
    results
  };
};

// Format results for display
const formatResults = (testResults) => {
  const formattedResults = [];
  
  testResults.forEach(result => {
    const { endpoint, config, results } = result;
    
    formattedResults.push({
      endpoint,
      description: config.description,
      method: config.method,
      path: config.path,
      metrics: {
        requests: {
          average: results.requests.average,
          mean: results.requests.mean,
          stddev: results.requests.stddev,
          min: results.requests.min,
          max: results.requests.max,
          total: results.requests.total,
          p99: results.requests.p99,
          p999: results.requests.p999
        },
        latency: {
          average: results.latency.average,
          mean: results.latency.mean,
          stddev: results.latency.stddev,
          min: results.latency.min,
          max: results.latency.max,
          p50: results.latency.p50,
          p75: results.latency.p75,
          p90: results.latency.p90,
          p99: results.latency.p99,
          p999: results.latency.p999
        },
        throughput: {
          average: results.throughput.average,
          mean: results.throughput.mean,
          stddev: results.throughput.stddev,
          min: results.throughput.min,
          max: results.throughput.max,
          total: results.throughput.total
        },
        errors: results.errors,
        timeouts: results.timeouts,
        non2xx: results.non2xx,
        successful: results.successful,
        resets: results.resets
      }
    });
  });
  
  return formattedResults;
};

// Print summary to console
const printSummary = (testResults) => {
  console.log('\n===================================================');
  console.log('Performance Test Summary');
  console.log('===================================================');
  
  testResults.forEach(result => {
    const { endpoint, config, results } = result;
    
    console.log(`\nEndpoint: ${config.description}`);
    console.log(`Method: ${config.method}`);
    console.log(`Path: ${config.path}`);
    console.log('---------------------------------------------------');
    console.log(`Requests/sec: ${results.requests.average.toFixed(2)}`);
    console.log(`Latency (avg): ${results.latency.average.toFixed(2)} ms`);
    console.log(`Latency (p99): ${results.latency.p99.toFixed(2)} ms`);
    console.log(`Throughput: ${(results.throughput.average / 1024 / 1024).toFixed(2)} MB/s`);
    console.log(`Errors: ${results.errors}`);
    console.log(`Non-2xx responses: ${results.non2xx}`);
    console.log(`Successful requests: ${results.successful}`);
  });
  
  console.log('\n===================================================');
};

// Save report to file
const saveReport = (report, filePath) => {
  const reportDir = path.dirname(filePath);
  
  // Create directory if it doesn't exist
  if (!fs.existsSync(reportDir)) {
    fs.mkdirSync(reportDir, { recursive: true });
  }
  
  // Save report
  fs.writeFileSync(filePath, JSON.stringify(report, null, 2));
  console.log(`\nReport saved to: ${filePath}`);
};

// Main function
const main = async () => {
  const options = parseArgs();
  const testResults = [];
  
  console.log('===================================================');
  console.log('Ingestor System API Performance Test');
  console.log('===================================================\n');
  
  // Run tests for specified endpoint or all endpoints
  if (options.endpoint === 'all') {
    // GET endpoints
    for (const endpoint of Object.keys(API_CONFIG.endpoints)) {
      testResults.push(await runTest(endpoint, options));
    }
    
    // POST endpoints - uncomment when POST tests are needed
    // for (const endpoint of Object.keys(API_CONFIG.postEndpoints)) {
    //   testResults.push(await runTest(endpoint, options, true));
    // }
  } else {
    // Run test for specific endpoint
    if (API_CONFIG.endpoints[options.endpoint]) {
      testResults.push(await runTest(options.endpoint, options));
    } else if (API_CONFIG.postEndpoints[options.endpoint]) {
      testResults.push(await runTest(options.endpoint, options, true));
    } else {
      console.error(`Error: Endpoint '${options.endpoint}' not found.`);
      process.exit(1);
    }
  }
  
  // Format and display results
  const formattedResults = formatResults(testResults);
  printSummary(testResults);
  
  // Save report
  saveReport({
    date: new Date().toISOString(),
    options,
    results: formattedResults
  }, options.report);
};

// Execute main function
main().catch(err => {
  console.error('Error:', err);
  process.exit(1);
});