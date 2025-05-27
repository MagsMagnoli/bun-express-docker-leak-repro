import express from "express";
import http from "node:http";

// Types for Bun's JavaScriptCore heap statistics
interface HeapStats {
  heapSize: number;
  heapCapacity: number;
  extraMemorySize: number;
  objectCount: number;
  protectedObjectCount: number;
  globalObjectCount: number;
  protectedGlobalObjectCount: number;
  objectTypeCounts: Record<string, number>;
  protectedObjectTypeCounts: Record<string, number>;
  heapSizeMB?: number;
  heapCapacityMB?: number;
  extraMemorySizeMB?: number;
}

interface SnapshotInfo {
  created: boolean;
  filename?: string;
  timestamp?: string;
  message: string;
  error?: string;
}

const app = express();
const PORT = process.env.PORT || 3000;

// Disable X-Powered-By header for security
app.disable('x-powered-by');

// Log all incoming requests at the raw HTTP level
const server = http.createServer(app);
server.on('request', (req, res) => {
  const timestamp = new Date().toISOString();
  console.log(`[${timestamp}] RAW HTTP: ${req.method} ${req.url} from ${req.socket.remoteAddress}`);
});

/**
 * Health check endpoint - minimal response
 */
app.get("/health", (req, res) => {
  res.status(200).json({ status: "ok" });
});

/**
 * Memory monitoring endpoint using Bun's JavaScriptCore heap statistics
 * Based on Bun's official documentation and best practices
 */
app.get("/memory", async (req, res) => {
  try {
    // Basic Node.js memory usage (RSS - Resident Set Size)
    const memoryUsage = process.memoryUsage();
    const memoryUsageMB = {
      rss: Math.round(memoryUsage.rss / 1024 / 1024), // MB
      heapUsed: Math.round(memoryUsage.heapUsed / 1024 / 1024), // MB
      heapTotal: Math.round(memoryUsage.heapTotal / 1024 / 1024), // MB
      external: Math.round(memoryUsage.external / 1024 / 1024), // MB
      arrayBuffers: Math.round(memoryUsage.arrayBuffers / 1024 / 1024), // MB
    };

    let heapStats: HeapStats | null = null;
    let snapshotInfo: SnapshotInfo | null = null;

    // Try to get Bun's JavaScriptCore heap statistics if available
    try {
      const { heapStats: bunHeapStats } = await import("bun:jsc");
      const rawHeapStats = bunHeapStats() as HeapStats;

      // Convert heap sizes to MB for readability
      heapStats = {
        ...rawHeapStats,
        heapSizeMB: Math.round(rawHeapStats.heapSize / 1024 / 1024),
        heapCapacityMB: Math.round(rawHeapStats.heapCapacity / 1024 / 1024),
        extraMemorySizeMB: Math.round(rawHeapStats.extraMemorySize / 1024 / 1024),
      };
    } catch (error) {
      console.log("Bun JSC heap stats not available, running in Node.js mode");
    }

    // Handle heap snapshot creation if requested
    if (req.query.snapshot === "true") {
      try {
        const { writeHeapSnapshot } = await import("v8");
        const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
        const filename = `heap-snapshot-${timestamp}.heapsnapshot`;

        writeHeapSnapshot(filename);
        snapshotInfo = {
          created: true,
          filename,
          timestamp: new Date().toISOString(),
          message: "Heap snapshot created. Load this file in Chrome DevTools Memory tab for analysis.",
        };
      } catch (snapshotError) {
        snapshotInfo = {
          created: false,
          error: "Failed to create heap snapshot",
          message: snapshotError instanceof Error ? snapshotError.message : "Unknown error",
        };
      }
    }

    // Calculate memory trend indicators
    const memoryTrend = {
      heapUtilization: Math.round((memoryUsage.heapUsed / memoryUsage.heapTotal) * 100),
      isHighMemoryUsage: memoryUsageMB.rss > 512, // Flag if RSS > 512MB
      recommendations: [] as string[],
    };

    // Add recommendations based on memory usage patterns
    if (memoryTrend.heapUtilization > 80) {
      memoryTrend.recommendations.push(
        "High heap utilization detected. Consider investigating potential memory leaks."
      );
    }

    if (memoryUsageMB.rss > 1024) {
      memoryTrend.recommendations.push(
        "High RSS memory usage (>1GB). Monitor for continuous growth over time."
      );
    }

    if (heapStats?.objectCount && heapStats.objectCount > 100000) {
      memoryTrend.recommendations.push(
        "High object count detected. Check for object retention issues."
      );
    }

    // Detect potential leak indicators from object type counts
    const leakIndicators: string[] = [];
    if (heapStats?.objectTypeCounts) {
      const { objectTypeCounts } = heapStats;

      // Check for suspicious object counts that indicate memory leaks
      if (objectTypeCounts.Headers && objectTypeCounts.Headers > 100) {
        leakIndicators.push(`High Headers count (${objectTypeCounts.Headers}) - potential HTTP object leak`);
      }

      if (objectTypeCounts.NodeHTTPResponse && objectTypeCounts.NodeHTTPResponse > 100) {
        leakIndicators.push(`High NodeHTTPResponse count (${objectTypeCounts.NodeHTTPResponse}) - potential HTTP object leak`);
      }

      if (objectTypeCounts.Arguments && objectTypeCounts.Arguments > 1000) {
        leakIndicators.push(`High Arguments count (${objectTypeCounts.Arguments}) - potential closure leak`);
      }

      if (objectTypeCounts.Promise && objectTypeCounts.Promise > 10000) {
        leakIndicators.push("High Promise count - check for unresolved promises");
      }

      if (objectTypeCounts.Array && objectTypeCounts.Array > 50000) {
        leakIndicators.push("High Array count - check for array retention");
      }

      if (objectTypeCounts.Function && objectTypeCounts.Function > 20000) {
        leakIndicators.push("High Function count - check for closure leaks");
      }
    }

    const response = {
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
      memory: {
        usage: memoryUsageMB,
        trend: memoryTrend,
        leakIndicators: leakIndicators.length > 0 ? leakIndicators : null,
      },
      heap: heapStats
        ? {
            statistics: heapStats,
            analysis: {
              totalObjects: heapStats.objectCount,
              protectedObjects: heapStats.protectedObjectCount,
              topObjectTypes: Object.entries(heapStats.objectTypeCounts)
                .sort(([, a], [, b]) => Number(b) - Number(a))
                .slice(0, 10)
                .map(([type, count]) => ({ type, count })),
              // Highlight HTTP-related objects for leak detection
              httpObjects: {
                Headers: heapStats.objectTypeCounts.Headers || 0,
                NodeHTTPResponse: heapStats.objectTypeCounts.NodeHTTPResponse || 0,
                Arguments: heapStats.objectTypeCounts.Arguments || 0,
                NodeHTTPServerSocket: heapStats.objectTypeCounts.NodeHTTPServerSocket || 0,
              },
            },
          }
        : null,
      snapshot: snapshotInfo,
      instructions: {
        heapSnapshot: "Add ?snapshot=true to create a heap snapshot file for Chrome DevTools analysis",
        monitoring: "Monitor this endpoint over time to detect memory leaks (look for continuously increasing RSS/heap usage)",
        analysis: "Use Chrome DevTools Memory tab to analyze heap snapshots and compare multiple snapshots to identify leaks",
        reproduction: "Run load test with: bun run load-test, then check memory with: bun run memory-check",
      },
    };

    res.status(200).json(response);
  } catch (error) {
    console.error("Error in memory endpoint:", error);
    res.status(500).json({
      error: "Failed to retrieve memory information",
      message: error instanceof Error ? error.message : "Unknown error",
      timestamp: new Date().toISOString(),
    });
  }
});

// Start the server
server.listen(PORT, () => {
  console.log(`🚀 Bun + Express memory leak reproduction server running on port ${PORT}`);
  console.log(`📊 Memory monitoring: http://localhost:${PORT}/memory`);
  console.log(`❤️  Health check: http://localhost:${PORT}/health`);
  console.log(`🔬 To reproduce leak: bun run load-test`);
  console.log(`📈 To check memory: bun run memory-check`);
});

// Graceful shutdown
process.on("SIGTERM", () => {
  console.log("Received SIGTERM, shutting down gracefully");
  server.close(() => {
    console.log("Server closed");
    process.exit(0);
  });
});

process.on("SIGINT", () => {
  console.log("Received SIGINT, shutting down gracefully");
  server.close(() => {
    console.log("Server closed");
    process.exit(0);
  });
}); 