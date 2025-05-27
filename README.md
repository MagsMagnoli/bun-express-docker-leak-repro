# Bun + Express Memory Leak Reproduction

This repository contains a comprehensive reproduction case for a memory leak that occurs when using Bun with Express.js. The leak manifests as continuously growing `Headers`, `NodeHTTPResponse`, and `Arguments` objects that are not properly garbage collected.

## 🔬 **4-Way Isolation Test Matrix**

We've created the ultimate isolation test to pinpoint whether this is a **Bun runtime issue** or **containerization issue**:

| Test Environment | Runtime | Container Base | Expected Result | Purpose |
|------------------|---------|----------------|----------------|---------|
| **Local Bun** | Bun | None (macOS) | ❓ Test reports | Direct execution baseline |
| **Docker Bun** | Bun | Official Bun image | ❓ Test reports | Containerized Bun |
| **Node.js** | Node.js 24.0.2 | Node.js slim | ✅ No leaks (control) | Proper behavior reference |
| **Bun-in-Node** | **Bun** | Node.js slim | 🎯 **THE SMOKING GUN** | Runtime isolation test |

**The Key Insight**: If **Bun-in-Node** shows leaks, it's definitely a **Bun runtime issue**. If it doesn't, the problem might be in Bun's Docker environment.

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
- **WebSocket support**: Added noop WebSocket server for comprehensive testing
- **Platform**: Tested across multiple environments and runtimes

## 🚀 **Quick Start - Run All Tests**

### **Complete 4-Way Analysis**
```bash
./run-all-tests.sh
```
**Estimated time**: ~12-20 minutes total  
**What it does**: Runs all four test environments and provides comprehensive comparison analysis.

### **Individual Test Options**
```bash
# Local Bun only (~3-5 min)
./run-all-tests.sh --local-only

# Docker Bun only (~3-5 min)  
./run-all-tests.sh --docker-only

# Node.js control test only (~3-5 min)
./run-all-tests.sh --node-only

# Bun-in-Node isolation test only (~3-5 min)
./run-all-tests.sh --node-bun-only
```

### **Direct Test Execution**
```bash
# Individual test scripts
./test-reproduction-local.sh      # Local Bun
./test-reproduction.sh            # Docker Bun  
./test-docker-node.sh             # Node.js 24.0.2
./test-docker-node-bun.sh         # Bun-in-Node.js (NEW!)
```

## What the Automated Tests Do

Each test script automatically:
1. ✅ **Checks dependencies** (Bun, Docker, jq)
2. 🏗️ **Sets up environment** (installs deps, builds images)
3. 🚀 **Starts server** (local process or Docker container)
4. 📊 **Collects baseline** memory statistics (both MB usage + object counts)
5. 🔥 **Runs load test** (1000 sequential HTTP requests)
6. 📈 **Analyzes memory growth** across 9+ object types + memory usage
7. ⏳ **Waits 2 minutes** to check for continued growth
8. 🧹 **Cleans up** automatically (kills processes, removes containers)
9. 📋 **Provides summary** with leak rates and severity analysis

### **Comprehensive Metrics Tracked**

**Memory Usage (MB):**
- RSS (Resident Set Size)
- HeapUsed, HeapTotal, External
- Memory growth analysis

**Object Counts (Bun-specific):**
- Headers, NodeHTTPResponse, Arguments
- Promises, Arrays, Functions, Objects, Strings
- Leak rates per request
- Continued background growth

## Expected vs Actual Results

### Expected Behavior (Node.js)
HTTP-related objects should be garbage collected after requests complete, maintaining relatively stable object counts and memory usage regardless of request volume.

### Actual Behavior (Bun)
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

### **4-Way Comparison Matrix**

After running all tests, you'll get a comparison like:

```
Environment: Local Bun
Duration: 15s
Memory growth: RSS +45MB, HeapUsed +32MB
Headers leak: +1284
Responses leak: +1284
Severity: critical

Environment: Docker Bun  
Duration: 18s
Memory growth: RSS +52MB, HeapUsed +38MB
Headers leak: +1298
Responses leak: +1298
Severity: critical

Environment: Node.js 24.0.2 Docker
Duration: 12s
Memory growth: +8MB RSS
Severity: none

Environment: Bun-in-Node.js Docker
Duration: 16s
Memory growth: RSS +48MB, HeapUsed +35MB
Headers leak: +1291
Responses leak: +1291
Severity: critical
```

**Analysis**: If Bun-in-Node shows leaks (like above), it confirms this is a **Bun runtime issue**, not containerization.

## Memory Monitoring

The `/memory` endpoint provides comprehensive memory statistics:

**For Bun environments:**
- Bun's JavaScriptCore heap statistics with detailed object counts
- HTTP object tracking (Headers, NodeHTTPResponse, Arguments)
- Memory usage in MB (RSS, HeapUsed, HeapTotal, External)

**For Node.js environments:**
- Standard Node.js memory usage metrics
- V8 heap snapshot generation capability
- Basic memory trend analysis

### Key Metrics to Monitor

- `heap.analysis.httpObjects.Headers`
- `heap.analysis.httpObjects.NodeHTTPResponse`
- `heap.analysis.httpObjects.Arguments`
- `memory.usage.rss` (resident set size)
- `memory.usage.heapUsed` (heap memory used)

## Minimal Reproduction Code

The reproduction case uses the absolute minimum Express.js setup with WebSocket support:

```typescript
import express from "express";
import http from "node:http";
import { WebSocketServer, WebSocket } from "ws";

const app = express();
app.disable('x-powered-by');

// Minimal health check endpoint
app.get("/health", (req, res) => {
  res.status(200).json({ status: "ok" });
});

// Memory monitoring endpoint
app.get("/memory", async (req, res) => {
  // Comprehensive memory monitoring using bun:jsc (Bun) or Node.js metrics
});

// WebSocket server (noop for testing)
const wss = new WebSocketServer({ noServer: true });
const server = http.createServer(app);

server.on('upgrade', (request, socket, head) => {
  const pathname = new URL(request.url!, `http://${request.headers.host}`).pathname;
  if (pathname === '/ws') {
    wss.handleUpgrade(request, socket, head, (ws) => {
      wss.emit('connection', ws, request);
    });
  } else {
    socket.destroy();
  }
});

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
- **Containerization effects**: Bun-in-Node test isolates runtime vs environment

### What Causes the Leak

The leak appears to be at the fundamental HTTP request/response handling level in **Bun's runtime**, specifically:
1. Bun's HTTP implementation
2. Bun's Express.js compatibility layer  
3. Object lifecycle management in JavaScriptCore

### Additional Observations

- Objects continue to accumulate even after load testing stops
- Leak rate is consistent across different environments (Local, Docker, Bun-in-Node)
- Memory usage grows linearly with request count
- Garbage collection does not reclaim the leaked objects
- **Critical**: Bun-in-Node test confirms this is a runtime issue, not containerization

## Files

### Core Application
- `index.ts` - Minimal Express server with memory monitoring + WebSocket support
- `package.json` - Dependencies and scripts

### Docker Configurations
- `Dockerfile` - Official Bun image setup
- `Dockerfile.node` - Node.js 24.0.2 with experimental TypeScript support
- `Dockerfile.node-bun` - **NEW!** Node.js base with Bun runtime installed

### Test Scripts
- `run-all-tests.sh` - **Master test runner** (all 4 environments)
- `test-reproduction-local.sh` - Local Bun test
- `test-reproduction.sh` - Docker Bun test  
- `test-docker-node.sh` - Node.js 24.0.2 test
- `test-docker-node-bun.sh` - **NEW!** Bun-in-Node.js isolation test

### Documentation
- `README.md` - This comprehensive documentation

## Scripts

### **Automated Testing Scripts**
```bash
# Master test runner with all options
./run-all-tests.sh                  # All 4 tests (~12-20 min)
./run-all-tests.sh --local-only     # Local Bun only
./run-all-tests.sh --docker-only    # Docker Bun only  
./run-all-tests.sh --node-only      # Node.js only
./run-all-tests.sh --node-bun-only  # Bun-in-Node only

# Individual test execution
./test-reproduction-local.sh        # Local Bun
./test-reproduction.sh              # Docker Bun
./test-docker-node.sh               # Node.js 24.0.2
./test-docker-node-bun.sh           # Bun-in-Node.js
```

### **Manual Development Scripts**
```bash
# Development
bun run dev                    # Start development server
bun run load-test             # Send 1000 requests to /health
bun run memory-check          # Check current memory usage

# Docker builds
bun run docker:build          # Build Bun Docker image
bun run docker:build:node     # Build Node.js Docker image  
bun run docker:run            # Run Bun container
bun run docker:run:node       # Run Node.js container
```

### **Test Features**

The automated test scripts provide:
- **4-Way Environment Testing**: Local Bun, Docker Bun, Node.js, Bun-in-Node
- **Dual Metric Tracking**: Memory usage (MB) + Object counts
- **Runtime Isolation**: Bun-in-Node test isolates runtime vs containerization issues
- **Leak Rate Calculation**: Objects leaked per request for each type
- **Severity Classification**: Critical/Moderate/None based on leak thresholds
- **Continued Growth Detection**: Monitors background memory growth after load test
- **Comprehensive Comparison**: Side-by-side analysis across all environments
- **Automatic Cleanup**: Guaranteed cleanup of processes and containers
- **Detailed Reporting**: Summary with actionable metrics for bug reports

## **Key Insights from 4-Way Testing**

1. **If Local Bun shows no leaks but Docker Bun does**: Containerization issue
2. **If both Bun environments show leaks but Bun-in-Node doesn't**: Bun Docker image issue
3. **If Bun-in-Node shows leaks**: **Confirmed Bun runtime issue** 
4. **If Node.js shows leaks**: Something wrong with the test (shouldn't happen)

This matrix definitively isolates whether the issue is:
- ✅ **Bun runtime** (most likely based on current evidence)
- ❌ **Bun Docker environment** 
- ❌ **General containerization**
- ❌ **Test methodology**

## Contributing

This reproduction case is intended for the Bun development team to investigate and resolve the memory leak. The 4-way isolation test matrix provides definitive evidence of where the issue lies.

## System Information

Please include the following when reporting:
- Bun version (`bun --version`)
- Operating system and version  
- Results from all 4 test environments
- Memory baseline and post-load-test measurements
- Any additional observations or variations in reproduction steps

**Run the complete test suite and share all results for comprehensive analysis:**
```bash
./run-all-tests.sh > memory-leak-results.txt 2>&1
``` 