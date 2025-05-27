#!/bin/bash

# Alpine + Bun Docker Memory Leak Test
# Tests Bun runtime in Alpine 3.19 container to isolate minimal Linux effects

set -e

echo "🔬 Alpine + Bun Docker Memory Leak Test"
echo "======================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if docker is installed
if ! command -v docker &> /dev/null; then
    echo -e "${RED}❌ Docker is not installed. Please install Docker first.${NC}"
    exit 1
fi

# Check if jq is installed (for JSON parsing)
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}⚠️  jq is not installed. JSON output will not be formatted.${NC}"
    JQ_AVAILABLE=false
else
    JQ_AVAILABLE=true
fi

echo -e "${BLUE}📋 System Information:${NC}"
echo "Docker version: $(docker --version)"
echo "OS: $(uname -s) $(uname -r)"
echo "Date: $(date)"
echo ""

# Build Docker image
echo -e "${BLUE}🏗️  Building Alpine + Bun Docker image...${NC}"
docker build -f Dockerfile.alpine-bun -t alpine-bun-memory-leak-repro .

# Start container in background
echo -e "${BLUE}🚀 Starting Alpine + Bun Docker container...${NC}"
CONTAINER_ID=$(docker run -d -p 3000:3000 --name alpine-bun-memory-leak-test alpine-bun-memory-leak-repro)

# Function to cleanup container
cleanup_container() {
    echo -e "${BLUE}🧹 Cleaning up Docker container...${NC}"
    docker stop $CONTAINER_ID 2>/dev/null || true
    docker rm $CONTAINER_ID 2>/dev/null || true
}

# Set trap to cleanup on exit
trap cleanup_container EXIT

# Wait for container to start
echo -e "${YELLOW}⏳ Waiting for container to start...${NC}"
sleep 5

# Function to check if server is running
check_server() {
    if curl -s http://localhost:3000/health > /dev/null; then
        return 0
    else
        return 1
    fi
}

# Verify server is running with retries
MAX_RETRIES=10
RETRY_COUNT=0
while ! check_server && [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    echo -e "${YELLOW}⏳ Waiting for server to be ready... (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)${NC}"
    sleep 2
    RETRY_COUNT=$((RETRY_COUNT + 1))
done

if ! check_server; then
    echo -e "${RED}❌ Server failed to start after $MAX_RETRIES attempts${NC}"
    docker logs $CONTAINER_ID
    exit 1
fi

echo -e "${GREEN}✅ Alpine + Bun Docker container is running and server is ready${NC}"

# Show container info
echo -e "${BLUE}📦 Container Information:${NC}"
echo "Container ID: $CONTAINER_ID"
echo "Base Image: Alpine 3.19"
echo "Runtime: Bun (installed in Alpine container)"
echo "Image: alpine-bun-memory-leak-repro"
echo ""

# Function to get memory stats (HTTP objects)
get_memory_stats() {
    if $JQ_AVAILABLE; then
        curl -s http://localhost:3000/memory | jq '.heap.analysis.httpObjects'
    else
        curl -s http://localhost:3000/memory
    fi
}

# Function to get memory usage (MB)
get_memory_usage() {
    if $JQ_AVAILABLE; then
        curl -s http://localhost:3000/memory | jq '.memory.usage'
    else
        curl -s http://localhost:3000/memory
    fi
}

# Get baseline memory
echo -e "${BLUE}📊 Getting baseline memory statistics...${NC}"
echo "Baseline HTTP Objects:"
BASELINE=$(get_memory_stats)
echo "$BASELINE"
echo ""

echo "Baseline Memory Usage:"
BASELINE_MEMORY=$(get_memory_usage)
echo "$BASELINE_MEMORY"
echo ""

# Extract baseline numbers if jq is available
if $JQ_AVAILABLE; then
    BASELINE_HEADERS=$(echo "$BASELINE" | jq -r '.Headers')
    BASELINE_RESPONSES=$(echo "$BASELINE" | jq -r '.NodeHTTPResponse')
    BASELINE_ARGUMENTS=$(echo "$BASELINE" | jq -r '.Arguments')
    BASELINE_SOCKETS=$(echo "$BASELINE" | jq -r '.NodeHTTPServerSocket')
    
    # Extract memory usage baseline
    BASELINE_RSS=$(echo "$BASELINE_MEMORY" | jq -r '.rss')
    BASELINE_HEAP_USED=$(echo "$BASELINE_MEMORY" | jq -r '.heapUsed')
    BASELINE_HEAP_TOTAL=$(echo "$BASELINE_MEMORY" | jq -r '.heapTotal')
    BASELINE_EXTERNAL=$(echo "$BASELINE_MEMORY" | jq -r '.external')
    
    echo "Baseline - Headers: $BASELINE_HEADERS, NodeHTTPResponse: $BASELINE_RESPONSES, Arguments: $BASELINE_ARGUMENTS, Sockets: $BASELINE_SOCKETS"
    echo "Baseline Memory - RSS: ${BASELINE_RSS}MB, HeapUsed: ${BASELINE_HEAP_USED}MB, HeapTotal: ${BASELINE_HEAP_TOTAL}MB, External: ${BASELINE_EXTERNAL}MB"
fi

# Run load test
echo -e "${BLUE}🔥 Running load test (1000 requests)...${NC}"
echo "This may take a moment..."

START_TIME=$(date +%s)
for i in {1..1000}; do
    curl -s http://localhost:3000/health > /dev/null
    if [ $((i % 100)) -eq 0 ]; then
        echo -e "${YELLOW}Progress: $i/1000 requests completed${NC}"
    fi
done
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo -e "${GREEN}✅ Load test completed in ${DURATION} seconds${NC}"
echo ""

# Get post-load-test memory
echo -e "${BLUE}📊 Getting post-load-test memory statistics...${NC}"
echo "Post-Load-Test HTTP Objects:"
POST_LOAD=$(get_memory_stats)
echo "$POST_LOAD"
echo ""

echo "Post-Load-Test Memory Usage:"
POST_LOAD_MEMORY=$(get_memory_usage)
echo "$POST_LOAD_MEMORY"
echo ""

# Calculate differences if jq is available
if $JQ_AVAILABLE; then
    POST_HEADERS=$(echo "$POST_LOAD" | jq -r '.Headers')
    POST_RESPONSES=$(echo "$POST_LOAD" | jq -r '.NodeHTTPResponse')
    POST_ARGUMENTS=$(echo "$POST_LOAD" | jq -r '.Arguments')
    POST_SOCKETS=$(echo "$POST_LOAD" | jq -r '.NodeHTTPServerSocket')
    
    # Extract memory usage post-load
    POST_RSS=$(echo "$POST_LOAD_MEMORY" | jq -r '.rss')
    POST_HEAP_USED=$(echo "$POST_LOAD_MEMORY" | jq -r '.heapUsed')
    POST_HEAP_TOTAL=$(echo "$POST_LOAD_MEMORY" | jq -r '.heapTotal')
    POST_EXTERNAL=$(echo "$POST_LOAD_MEMORY" | jq -r '.external')
    
    HEADERS_DIFF=$((POST_HEADERS - BASELINE_HEADERS))
    RESPONSES_DIFF=$((POST_RESPONSES - BASELINE_RESPONSES))
    ARGUMENTS_DIFF=$((POST_ARGUMENTS - BASELINE_ARGUMENTS))
    SOCKETS_DIFF=$((POST_SOCKETS - BASELINE_SOCKETS))
    
    # Calculate memory differences
    RSS_DIFF=$((POST_RSS - BASELINE_RSS))
    HEAP_USED_DIFF=$((POST_HEAP_USED - BASELINE_HEAP_USED))
    HEAP_TOTAL_DIFF=$((POST_HEAP_TOTAL - BASELINE_HEAP_TOTAL))
    EXTERNAL_DIFF=$((POST_EXTERNAL - BASELINE_EXTERNAL))
    
    echo -e "${BLUE}📈 HTTP Objects Memory Leak Analysis:${NC}"
    echo "Headers: $BASELINE_HEADERS → $POST_HEADERS (+$HEADERS_DIFF)"
    echo "NodeHTTPResponse: $BASELINE_RESPONSES → $POST_RESPONSES (+$RESPONSES_DIFF)"
    echo "Arguments: $BASELINE_ARGUMENTS → $POST_ARGUMENTS (+$ARGUMENTS_DIFF)"
    echo "NodeHTTPServerSocket: $BASELINE_SOCKETS → $POST_SOCKETS (+$SOCKETS_DIFF)"
    echo ""
    
    echo -e "${BLUE}📈 Memory Usage Analysis:${NC}"
    echo "RSS: ${BASELINE_RSS}MB → ${POST_RSS}MB (+${RSS_DIFF}MB)"
    echo "HeapUsed: ${BASELINE_HEAP_USED}MB → ${POST_HEAP_USED}MB (+${HEAP_USED_DIFF}MB)"
    echo "HeapTotal: ${BASELINE_HEAP_TOTAL}MB → ${POST_HEAP_TOTAL}MB (+${HEAP_TOTAL_DIFF}MB)"
    echo "External: ${BASELINE_EXTERNAL}MB → ${POST_EXTERNAL}MB (+${EXTERNAL_DIFF}MB)"
    echo ""
    
    # Calculate leak rates
    HEADERS_LEAK_RATE=$(echo "scale=2; $HEADERS_DIFF / 1000" | bc 2>/dev/null || echo "~$((HEADERS_DIFF / 1000))")
    RESPONSES_LEAK_RATE=$(echo "scale=2; $RESPONSES_DIFF / 1000" | bc 2>/dev/null || echo "~$((RESPONSES_DIFF / 1000))")
    
    echo -e "${BLUE}📊 Leak Rates (objects per request):${NC}"
    echo "Headers: ~$HEADERS_LEAK_RATE"
    echo "NodeHTTPResponse: ~$RESPONSES_LEAK_RATE"
    echo ""
    
    # Determine leak severity
    if [ $HEADERS_DIFF -gt 500 ] || [ $RESPONSES_DIFF -gt 500 ] || [ $SOCKETS_DIFF -gt 100 ]; then
        LEAK_SEVERITY="critical"
        echo -e "${RED}🚨 CRITICAL MEMORY LEAK DETECTED IN ALPINE + BUN!${NC}"
        echo "Significant object count increases detected"
        echo "This confirms containerization triggers Bun's memory leak"
    elif [ $HEADERS_DIFF -gt 100 ] || [ $RESPONSES_DIFF -gt 100 ] || [ $SOCKETS_DIFF -gt 50 ]; then
        LEAK_SEVERITY="moderate"
        echo -e "${YELLOW}⚠️  MODERATE MEMORY LEAK DETECTED IN ALPINE + BUN${NC}"
        echo "Some objects are not being garbage collected properly"
    else
        LEAK_SEVERITY="none"
        echo -e "${GREEN}✅ No significant memory leak detected in Alpine + Bun${NC}"
        echo "Object counts remained relatively stable"
    fi
fi

# Wait and check for continued growth
echo -e "${BLUE}⏳ Waiting 2 minutes to check for continued growth...${NC}"
sleep 120

echo -e "${BLUE}📊 Getting delayed memory statistics...${NC}"
DELAYED=$(get_memory_stats)
echo "Delayed Check HTTP Objects:"
echo "$DELAYED"

echo -e "${GREEN}✅ Alpine + Bun test completed!${NC}"
echo ""
echo -e "${BLUE}📋 Alpine + Bun Test Summary:${NC}"
echo "Duration: $DURATION seconds"
echo "Base Container: Alpine 3.19"
echo "Runtime: Bun (installed in Alpine container)"
echo "Container: alpine-bun-memory-leak-repro"
if $JQ_AVAILABLE; then
    echo "Memory growth: RSS +${RSS_DIFF}MB, HeapUsed +${HEAP_USED_DIFF}MB"
    echo "HTTP Objects leak: +$HEADERS_DIFF Headers, +$RESPONSES_DIFF NodeHTTPResponse, +$SOCKETS_DIFF Sockets"
    echo "Leak severity: $LEAK_SEVERITY"
fi
echo ""
echo -e "${BLUE}🔬 Containerization Analysis:${NC}"
echo "This test helps isolate whether the leak is triggered by:"
echo "- Specific Linux distributions (Ubuntu vs Alpine vs Debian)"
echo "- Container runtime environment vs local execution"
echo "- Docker-specific vs general containerization effects" 