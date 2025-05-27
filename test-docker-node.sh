#!/bin/bash

# Node.js + Express Memory Leak Reproduction Test Script (Docker Version)
# This script automates the reproduction steps using Node.js 24.0.2 with experimental TypeScript support

set -e

echo "🟢 Node.js + Express Memory Leak Reproduction Test (Docker)"
echo "=========================================================="

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
echo -e "${BLUE}🏗️  Building Node.js Docker image...${NC}"
docker build -f Dockerfile.node -t node-memory-leak-repro .

# Start container in background
echo -e "${BLUE}🚀 Starting Node.js Docker container...${NC}"
CONTAINER_ID=$(docker run -d -p 3000:3000 --name node-memory-leak-test node-memory-leak-repro)

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

echo -e "${GREEN}✅ Node.js Docker container is running and server is ready${NC}"

# Show container info
echo -e "${BLUE}📦 Container Information:${NC}"
echo "Container ID: $CONTAINER_ID"
echo "Image: node-memory-leak-repro (Node.js 24.0.2 with --experimental-strip-types)"
echo ""

# Function to get memory stats (both usage and heap info)
get_memory_stats() {
    if $JQ_AVAILABLE; then
        curl -s http://localhost:3000/memory
    else
        curl -s http://localhost:3000/memory
    fi
}

# Function to get Node.js memory usage
get_node_memory() {
    if $JQ_AVAILABLE; then
        curl -s http://localhost:3000/memory | jq '.memory.usage'
    else
        curl -s http://localhost:3000/memory
    fi
}

# Function to get heap analysis (if available)
get_heap_analysis() {
    if $JQ_AVAILABLE; then
        curl -s http://localhost:3000/memory | jq '.heap.analysis.httpObjects // null'
    else
        curl -s http://localhost:3000/memory
    fi
}

# Get baseline memory
echo -e "${BLUE}📊 Getting baseline memory statistics...${NC}"
echo "Baseline Node.js Memory Usage:"
BASELINE_MEMORY=$(get_node_memory)
echo "$BASELINE_MEMORY"
echo ""

# Try to get heap analysis (Node.js won't have object counts like Bun, but let's check)
echo "Baseline Heap Analysis:"
BASELINE_HEAP=$(get_heap_analysis)
echo "$BASELINE_HEAP"
echo ""

# Extract baseline numbers if jq is available
if $JQ_AVAILABLE; then
    BASELINE_RSS=$(echo "$BASELINE_MEMORY" | jq -r '.rss')
    BASELINE_HEAP_USED=$(echo "$BASELINE_MEMORY" | jq -r '.heapUsed')
    BASELINE_HEAP_TOTAL=$(echo "$BASELINE_MEMORY" | jq -r '.heapTotal')
    BASELINE_EXTERNAL=$(echo "$BASELINE_MEMORY" | jq -r '.external')
    
    echo "Baseline - RSS: ${BASELINE_RSS}MB, HeapUsed: ${BASELINE_HEAP_USED}MB, HeapTotal: ${BASELINE_HEAP_TOTAL}MB, External: ${BASELINE_EXTERNAL}MB"
    
    # Check if we have heap object counts (unlikely in Node.js but possible with heap snapshots)
    if [ "$BASELINE_HEAP" != "null" ] && [ -n "$BASELINE_HEAP" ]; then
        BASELINE_HEADERS=$(echo "$BASELINE_HEAP" | jq -r '.Headers // 0')
        BASELINE_RESPONSES=$(echo "$BASELINE_HEAP" | jq -r '.NodeHTTPResponse // 0')
        BASELINE_ARGUMENTS=$(echo "$BASELINE_HEAP" | jq -r '.Arguments // 0')
        BASELINE_SOCKETS=$(echo "$BASELINE_HEAP" | jq -r '.NodeHTTPServerSocket // 0')
        
        echo "Baseline HTTP Objects - Headers: $BASELINE_HEADERS, NodeHTTPResponse: $BASELINE_RESPONSES, Arguments: $BASELINE_ARGUMENTS, Sockets: $BASELINE_SOCKETS"
        TRACK_OBJECTS=true
    else
        echo "Node.js heap object tracking not available (expected - Node.js doesn't have Bun's heapStats)"
        TRACK_OBJECTS=false
    fi
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
echo "Post-Load-Test Node.js Memory Usage:"
POST_LOAD_MEMORY=$(get_node_memory)
echo "$POST_LOAD_MEMORY"
echo ""

echo "Post-Load-Test Heap Analysis:"
POST_LOAD_HEAP=$(get_heap_analysis)
echo "$POST_LOAD_HEAP"
echo ""

# Calculate differences if jq is available
if $JQ_AVAILABLE; then
    POST_RSS=$(echo "$POST_LOAD_MEMORY" | jq -r '.rss')
    POST_HEAP_USED=$(echo "$POST_LOAD_MEMORY" | jq -r '.heapUsed')
    POST_HEAP_TOTAL=$(echo "$POST_LOAD_MEMORY" | jq -r '.heapTotal')
    POST_EXTERNAL=$(echo "$POST_LOAD_MEMORY" | jq -r '.external')
    
    RSS_DIFF=$((POST_RSS - BASELINE_RSS))
    HEAP_USED_DIFF=$((POST_HEAP_USED - BASELINE_HEAP_USED))
    HEAP_TOTAL_DIFF=$((POST_HEAP_TOTAL - BASELINE_HEAP_TOTAL))
    EXTERNAL_DIFF=$((POST_EXTERNAL - BASELINE_EXTERNAL))
    
    echo -e "${BLUE}📈 Node.js Memory Analysis:${NC}"
    echo "RSS: ${BASELINE_RSS}MB → ${POST_RSS}MB (+${RSS_DIFF}MB)"
    echo "HeapUsed: ${BASELINE_HEAP_USED}MB → ${POST_HEAP_USED}MB (+${HEAP_USED_DIFF}MB)"
    echo "HeapTotal: ${BASELINE_HEAP_TOTAL}MB → ${POST_HEAP_TOTAL}MB (+${HEAP_TOTAL_DIFF}MB)"
    echo "External: ${BASELINE_EXTERNAL}MB → ${POST_EXTERNAL}MB (+${EXTERNAL_DIFF}MB)"
    echo ""
    
    # Check object count differences if we're tracking them
    if [ "$TRACK_OBJECTS" = true ] && [ "$POST_LOAD_HEAP" != "null" ] && [ -n "$POST_LOAD_HEAP" ]; then
        POST_HEADERS=$(echo "$POST_LOAD_HEAP" | jq -r '.Headers // 0')
        POST_RESPONSES=$(echo "$POST_LOAD_HEAP" | jq -r '.NodeHTTPResponse // 0')
        POST_ARGUMENTS=$(echo "$POST_LOAD_HEAP" | jq -r '.Arguments // 0')
        POST_SOCKETS=$(echo "$POST_LOAD_HEAP" | jq -r '.NodeHTTPServerSocket // 0')
        
        HEADERS_DIFF=$((POST_HEADERS - BASELINE_HEADERS))
        RESPONSES_DIFF=$((POST_RESPONSES - BASELINE_RESPONSES))
        ARGUMENTS_DIFF=$((POST_ARGUMENTS - BASELINE_ARGUMENTS))
        SOCKETS_DIFF=$((POST_SOCKETS - BASELINE_SOCKETS))
        
        echo -e "${BLUE}📈 HTTP Objects Analysis:${NC}"
        echo "Headers: $BASELINE_HEADERS → $POST_HEADERS (+$HEADERS_DIFF)"
        echo "NodeHTTPResponse: $BASELINE_RESPONSES → $POST_RESPONSES (+$RESPONSES_DIFF)"
        echo "Arguments: $BASELINE_ARGUMENTS → $POST_ARGUMENTS (+$ARGUMENTS_DIFF)"
        echo "NodeHTTPServerSocket: $BASELINE_SOCKETS → $POST_SOCKETS (+$SOCKETS_DIFF)"
        echo ""
        
        # Check for object leaks (Node.js should have minimal object growth)
        if [ $HEADERS_DIFF -gt 50 ] || [ $RESPONSES_DIFF -gt 50 ] || [ $ARGUMENTS_DIFF -gt 100 ]; then
            echo -e "${YELLOW}⚠️  Unexpected HTTP object growth in Node.js!${NC}"
            echo "HTTP Objects leak: +$HEADERS_DIFF Headers, +$RESPONSES_DIFF NodeHTTPResponse, +$ARGUMENTS_DIFF Arguments"
        else
            echo -e "${GREEN}✅ HTTP object counts stable in Node.js (expected)${NC}"
        fi
    fi
    
    # Determine leak severity for Node.js (should be minimal/none)
    if [ $RSS_DIFF -gt 50 ] || [ $HEAP_USED_DIFF -gt 30 ]; then
        LEAK_SEVERITY="moderate"
        echo -e "${YELLOW}⚠️  Unexpected memory growth detected in Node.js${NC}"
    elif [ $RSS_DIFF -gt 20 ] || [ $HEAP_USED_DIFF -gt 10 ]; then
        LEAK_SEVERITY="minor"
        echo -e "${YELLOW}⚠️  Minor memory growth detected in Node.js${NC}"
    else
        LEAK_SEVERITY="none"
        echo -e "${GREEN}✅ Node.js memory usage appears stable (expected behavior)${NC}"
    fi
    
    echo "Leak severity: $LEAK_SEVERITY"
fi

# Wait and check for continued growth
echo -e "${BLUE}⏳ Waiting 2 minutes to check for continued memory growth...${NC}"
sleep 120

echo -e "${BLUE}📊 Getting final memory statistics after wait...${NC}"
FINAL_MEMORY=$(get_node_memory)
echo "Final Node.js Memory Usage:"
echo "$FINAL_MEMORY"

FINAL_HEAP=$(get_heap_analysis)
echo "Final Heap Analysis:"
echo "$FINAL_HEAP"

if $JQ_AVAILABLE; then
    FINAL_RSS=$(echo "$FINAL_MEMORY" | jq -r '.rss')
    FINAL_HEAP_USED=$(echo "$FINAL_MEMORY" | jq -r '.heapUsed')
    
    CONTINUED_RSS_DIFF=$((FINAL_RSS - POST_RSS))
    CONTINUED_HEAP_DIFF=$((FINAL_HEAP_USED - POST_HEAP_USED))
    
    echo ""
    echo -e "${BLUE}📈 Continued Growth Analysis:${NC}"
    echo "RSS continued growth: +${CONTINUED_RSS_DIFF}MB"
    echo "HeapUsed continued growth: +${CONTINUED_HEAP_DIFF}MB"
    
    # Check continued object growth if tracking
    if [ "$TRACK_OBJECTS" = true ] && [ "$FINAL_HEAP" != "null" ] && [ -n "$FINAL_HEAP" ]; then
        FINAL_HEADERS=$(echo "$FINAL_HEAP" | jq -r '.Headers // 0')
        FINAL_RESPONSES=$(echo "$FINAL_HEAP" | jq -r '.NodeHTTPResponse // 0')
        
        CONTINUED_HEADERS_DIFF=$((FINAL_HEADERS - POST_HEADERS))
        CONTINUED_RESPONSES_DIFF=$((FINAL_RESPONSES - POST_RESPONSES))
        
        echo "HTTP Objects continued growth: +${CONTINUED_HEADERS_DIFF} Headers, +${CONTINUED_RESPONSES_DIFF} NodeHTTPResponse"
        
        if [ $CONTINUED_HEADERS_DIFF -gt 10 ] || [ $CONTINUED_RESPONSES_DIFF -gt 10 ]; then
            echo -e "${YELLOW}⚠️  Continued HTTP object growth detected${NC}"
        fi
    fi
    
    if [ $CONTINUED_RSS_DIFF -gt 10 ] || [ $CONTINUED_HEAP_DIFF -gt 5 ]; then
        echo -e "${YELLOW}⚠️  Continued memory growth detected - potential background leak${NC}"
    else
        echo -e "${GREEN}✅ No significant continued growth - memory appears stable${NC}"
    fi
fi

echo ""
echo -e "${BLUE}📋 Node.js Test Summary:${NC}"
echo "Duration: $DURATION seconds"
echo "Runtime: Node.js 24.0.2 with --experimental-strip-types"
echo "Container: node-memory-leak-repro"
if $JQ_AVAILABLE; then
    echo "Memory growth: RSS +${RSS_DIFF}MB, HeapUsed +${HEAP_USED_DIFF}MB"
    if [ "$TRACK_OBJECTS" = true ]; then
        echo "HTTP Objects leak: +$HEADERS_DIFF Headers, +$RESPONSES_DIFF NodeHTTPResponse, +$ARGUMENTS_DIFF Arguments"
    fi
    echo "Leak severity: $LEAK_SEVERITY"
fi
echo ""
echo -e "${GREEN}✅ Node.js Docker test completed!${NC}"
echo -e "${BLUE}💡 Expected: Node.js should show minimal memory growth compared to Bun${NC}" 