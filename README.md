# Bun + Express Memory Leak Reproduction

This repository contains a minimal reproduction case for a memory leak that occurs when using Bun with Express.js. The leak manifests as continuously growing `Headers`, `NodeHTTPResponse`, and `Arguments` objects that are not properly garbage collected.

## Issue Description

When running a minimal Express.js server on Bun, HTTP-related objects accumulate in memory with each request and are not properly garbage collected. This leads to a memory leak that grows proportionally with the number of HTTP requests processed.

### Observed Behavior

- **Headers objects**: Grow by ~1.3 per HTTP request
- **NodeHTTPResponse objects**: Grow by ~1.3 per HTTP request  
- **Arguments objects**: Grow by ~1.3 per HTTP request
- **Memory growth**: Continuous increase in heap usage over time
- **Persistence**: Objects remain in memory even after requests complete

### Environment

- **Bun version**: Latest (as of reproduction)
- **Express version**: ^4.19.2
- **Node.js compatibility**: Issue occurs specifically with Bun runtime
- **Platform**: Tested on multiple environments

## Reproduction Steps

### Automated Testing (Recommended)

We provide comprehensive test scripts that automate the entire reproduction process:

#### 🚀 **Quick Start - Run All Tests**
```bash
./run-all-tests.sh
```
This runs both local and Docker tests, providing a complete comparison.

#### 🏠 **Local Bun Test Only**
```bash
./run-all-tests.sh --local-only
# OR
./test-reproduction-local.sh
```

#### 🐳 **Docker Test Only**
```bash
./run-all-tests.sh --docker-only
# OR
./test-reproduction.sh
```

### What the Automated Tests Do

Each test script automatically:
1. ✅ **Checks dependencies** (Bun, Docker, jq)
2. 🏗️ **Sets up environment** (installs deps, builds images)
3. 🚀 **Starts server** (local process or Docker container)
4. 📊 **Collects baseline** memory statistics
5. 🔥 **Runs load test** (1000 sequential HTTP requests)
6. 📈 **Analyzes memory growth** across 9+ object types
7. ⏳ **Waits 2 minutes** to check for continued growth
8. 🧹 **Cleans up** automatically (kills processes, removes containers)
9. 📋 **Provides summary** with leak rates and severity analysis

### Manual Testing (Advanced)

If you prefer manual testing or need to debug specific steps:

#### Local Development

1. **Install dependencies**:
   ```bash
   bun install
   ```

2. **Start the server**:
   ```bash
   bun run dev
   ```

3. **Check baseline memory**:
   ```bash
   bun run memory-check
   ```

4. **Run load test**:
   ```bash
   bun run load-test
   ```

5. **Check memory after load test**:
   ```bash
   bun run memory-check
   ```

#### Docker Testing

1. **Build and run**:
   ```bash
   bun run docker:build
   bun run docker:run
   ```

2. **Manual testing**:
   ```bash
   # Check memory
   curl -s http://localhost:3000/memory | jq '.heap.analysis.httpObjects'
   
   # Run load test
   for i in {1..1000}; do curl -s http://localhost:3000/health > /dev/null; done
   
   # Check memory again
   curl -s http://localhost:3000/memory | jq '.heap.analysis.httpObjects'
   ```

## Expected vs Actual Results

### Expected Behavior
HTTP-related objects should be garbage collected after requests complete, maintaining relatively stable object counts regardless of request volume.

### Actual Behavior
```json
// Before load test
{
  "Headers": 54,
  "NodeHTTPResponse": 50,
  "Arguments": 67
}

// After 1000 requests
{
  "Headers": 1338,
  "NodeHTTPResponse": 1334,
  "Arguments": 1352
}
```

**Result**: ~1.3 objects leaked per request, with no garbage collection occurring.

## Memory Monitoring

The `/memory` endpoint provides comprehensive memory statistics using Bun's JavaScriptCore heap statistics:

- **Basic memory usage**: RSS, heap used/total, external memory
- **Object type counts**: Detailed breakdown of all object types in memory
- **Leak indicators**: Automatic detection of suspicious object counts
- **HTTP object tracking**: Specific monitoring of HTTP-related objects
- **Heap snapshots**: Optional V8 heap snapshot generation for detailed analysis

### Key Metrics to Monitor

- `heap.analysis.httpObjects.Headers`
- `heap.analysis.httpObjects.NodeHTTPResponse`
- `heap.analysis.httpObjects.Arguments`
- `heap.statistics.objectCount` (total objects)
- `memory.usage.rss` (resident set size)

## Minimal Reproduction Code

The reproduction case uses the absolute minimum Express.js setup:

```typescript
import express from "express";
import http from "node:http";

const app = express();
app.disable('x-powered-by');

// Minimal health check endpoint
app.get("/health", (req, res) => {
  res.status(200).json({ status: "ok" });
});

// Memory monitoring endpoint with Bun's heap statistics
app.get("/memory", async (req, res) => {
  // ... comprehensive memory monitoring using bun:jsc
});

const server = http.createServer(app);
server.listen(3000);
```

## Investigation Notes

### What We've Ruled Out

- **Express middleware**: Leak persists with zero middleware
- **Request logging**: Leak occurs without any logging
- **Error handling**: Leak occurs without error handlers
- **Static file serving**: Leak occurs with only JSON endpoints
- **Authentication**: Leak occurs without auth middleware
- **Third-party libraries**: Leak occurs with minimal dependencies

### What Causes the Leak

The leak appears to be at the fundamental HTTP request/response handling level, either in:
1. Bun's HTTP implementation
2. Bun's Express.js compatibility layer
3. Object lifecycle management in JavaScriptCore

### Additional Observations

- Objects continue to accumulate even after load testing stops
- Leak rate is consistent across different environments
- Memory usage grows linearly with request count
- Garbage collection does not reclaim the leaked objects

## Files

### Core Application
- `index.ts` - Minimal Express server with memory monitoring
- `package.json` - Dependencies and scripts
- `Dockerfile` - Container setup with latest Bun

### Test Scripts
- `run-all-tests.sh` - **Master test runner** (runs both local and Docker tests)
- `test-reproduction-local.sh` - **Local Bun test** with comprehensive memory analysis
- `test-reproduction.sh` - **Docker test** with comprehensive memory analysis

### Documentation
- `README.md` - This documentation

## Scripts

### Automated Testing Scripts
- `./run-all-tests.sh` - Run both local and Docker tests with comparison
- `./run-all-tests.sh --local-only` - Run only local Bun test
- `./run-all-tests.sh --docker-only` - Run only Docker test
- `./test-reproduction-local.sh` - Direct local test execution
- `./test-reproduction.sh` - Direct Docker test execution

### Manual Development Scripts
- `bun run dev` - Start development server
- `bun run load-test` - Send 1000 requests to /health
- `bun run memory-check` - Check current memory usage
- `bun run docker:build` - Build Docker image
- `bun run docker:run` - Run Docker container

### Test Features

The automated test scripts provide:
- **Comprehensive Memory Analysis**: Monitors 9+ object types (Headers, NodeHTTPResponse, Promises, Arrays, Functions, etc.)
- **Leak Rate Calculation**: Objects leaked per request for each type
- **Severity Classification**: Critical/Moderate/None based on leak thresholds
- **Continued Growth Detection**: Monitors background memory growth after load test
- **Environment Comparison**: Compare leak behavior between local and Docker
- **Automatic Cleanup**: Guaranteed cleanup of processes and containers
- **Detailed Reporting**: Summary with actionable metrics for bug reports

## Contributing

This reproduction case is intended for the Bun development team to investigate and resolve the memory leak. If you can reproduce this issue or have additional insights, please contribute to the investigation.

## System Information

Please include the following when reporting:
- Bun version (`bun --version`)
- Operating system and version
- Memory baseline and post-load-test measurements
- Any additional observations or variations in reproduction steps 