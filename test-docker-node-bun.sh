#!/bin/bash

# Bun-in-Node.js Docker Memory Leak Reproduction Test Script
# This script tests Bun runtime inside a Node.js 24.0.2 container to isolate runtime vs container issues

set -e

echo "🔬 Bun-in-Node.js Docker Memory Leak Reproduction Test"
echo "===================================================="

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
echo -e "${BLUE}🏗️  Building Bun-in-Node.js Docker image...${NC}"
docker build -f Dockerfile.node-bun -t node-bun-memory-leak-repro .

# Start container in background
echo -e "${BLUE}🚀 Starting Bun-in-Node.js Docker container...${NC}"
CONTAINER_ID=$(docker run -d -p 3000:3000 --name node-bun-memory-leak-test node-bun-memory-leak-repro)

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

echo -e "${GREEN}✅ Bun-in-Node.js Docker container is running and server is ready${NC}"

# Show container info
echo -e "${BLUE}📦 Container Information:${NC}"
echo "Container ID: $CONTAINER_ID"
echo "Base Image: Node.js 24.0.2-slim"
echo "Runtime: Bun (installed inside Node.js container)"
echo "Image: node-bun-memory-leak-repro"
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

# Function to get all object type counts for comprehensive leak detection
get_all_object_counts() {
    if $JQ_AVAILABLE; then
        curl -s http://localhost:3000/memory | jq '.heap.statistics.objectTypeCounts'
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
    
    # Get additional object types for comprehensive leak detection
    echo -e "${BLUE}📊 Getting comprehensive baseline object counts...${NC}"
    BASELINE_ALL=$(get_all_object_counts)
    if [ "$BASELINE_ALL" != "null" ] && [ -n "$BASELINE_ALL" ]; then
        BASELINE_PROMISES=$(echo "$BASELINE_ALL" | jq -r '.Promise // 0')
        BASELINE_ARRAYS=$(echo "$BASELINE_ALL" | jq -r '.Array // 0')
        BASELINE_FUNCTIONS=$(echo "$BASELINE_ALL" | jq -r '.Function // 0')
        BASELINE_OBJECTS=$(echo "$BASELINE_ALL" | jq -r '.Object // 0')
        BASELINE_STRINGS=$(echo "$BASELINE_ALL" | jq -r '.String // 0')
        
        echo "Additional Baseline - Promises: $BASELINE_PROMISES, Arrays: $BASELINE_ARRAYS, Functions: $BASELINE_FUNCTIONS, Objects: $BASELINE_OBJECTS, Strings: $BASELINE_STRINGS"
        TRACK_OBJECTS=true
    else
        echo "Bun heap object tracking not available in this environment"
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
    
    # Check additional object types if available
    if [ "$TRACK_OBJECTS" = true ]; then
        POST_ALL=$(get_all_object_counts)
        if [ "$POST_ALL" != "null" ] && [ -n "$POST_ALL" ]; then
            POST_PROMISES=$(echo "$POST_ALL" | jq -r '.Promise // 0')
            POST_ARRAYS=$(echo "$POST_ALL" | jq -r '.Array // 0')
            POST_FUNCTIONS=$(echo "$POST_ALL" | jq -r '.Function // 0')
            POST_OBJECTS=$(echo "$POST_ALL" | jq -r '.Object // 0')
            POST_STRINGS=$(echo "$POST_ALL" | jq -r '.String // 0')
            
            PROMISES_DIFF=$((POST_PROMISES - BASELINE_PROMISES))
            ARRAYS_DIFF=$((POST_ARRAYS - BASELINE_ARRAYS))
            FUNCTIONS_DIFF=$((POST_FUNCTIONS - BASELINE_FUNCTIONS))
            OBJECTS_DIFF=$((POST_OBJECTS - BASELINE_OBJECTS))
            STRINGS_DIFF=$((POST_STRINGS - BASELINE_STRINGS))
            
            echo -e "${BLUE}📈 General Objects Memory Leak Analysis:${NC}"
            echo "Promises: $BASELINE_PROMISES → $POST_PROMISES (+$PROMISES_DIFF)"
            echo "Arrays: $BASELINE_ARRAYS → $POST_ARRAYS (+$ARRAYS_DIFF)"
            echo "Functions: $BASELINE_FUNCTIONS → $POST_FUNCTIONS (+$FUNCTIONS_DIFF)"
            echo "Objects: $BASELINE_OBJECTS → $POST_OBJECTS (+$OBJECTS_DIFF)"
            echo "Strings: $BASELINE_STRINGS → $POST_STRINGS (+$STRINGS_DIFF)"
            echo ""
        fi
    fi
    
    # Calculate leak rates
    HEADERS_LEAK_RATE=$(echo "scale=2; $HEADERS_DIFF / 1000" | bc 2>/dev/null || echo "~$((HEADERS_DIFF / 1000))")
    RESPONSES_LEAK_RATE=$(echo "scale=2; $RESPONSES_DIFF / 1000" | bc 2>/dev/null || echo "~$((RESPONSES_DIFF / 1000))")
    
    echo -e "${BLUE}📊 Leak Rates (objects per request):${NC}"
    echo "Headers: ~$HEADERS_LEAK_RATE"
    echo "NodeHTTPResponse: ~$RESPONSES_LEAK_RATE"
    if [ "$TRACK_OBJECTS" = true ] && [ -n "$PROMISES_DIFF" ]; then
        PROMISES_LEAK_RATE=$(echo "scale=2; $PROMISES_DIFF / 1000" | bc 2>/dev/null || echo "~$((PROMISES_DIFF / 1000))")
        echo "Promises: ~$PROMISES_LEAK_RATE"
    fi
    echo ""
    
    # Comprehensive leak detection
    LEAK_DETECTED=false
    LEAK_SEVERITY="none"
    LEAK_TYPES=()
    
    # Check HTTP objects
    if [ $HEADERS_DIFF -gt 500 ] || [ $RESPONSES_DIFF -gt 500 ] || [ $SOCKETS_DIFF -gt 100 ]; then
        LEAK_DETECTED=true
        LEAK_SEVERITY="critical"
        LEAK_TYPES+=("HTTP objects")
    elif [ $HEADERS_DIFF -gt 100 ] || [ $RESPONSES_DIFF -gt 100 ] || [ $SOCKETS_DIFF -gt 50 ]; then
        LEAK_DETECTED=true
        if [ "$LEAK_SEVERITY" != "critical" ]; then
            LEAK_SEVERITY="moderate"
        fi
        LEAK_TYPES+=("HTTP objects")
    fi
    
    # Check general objects if available
    if [ "$TRACK_OBJECTS" = true ] && [ -n "$PROMISES_DIFF" ]; then
        if [ $PROMISES_DIFF -gt 5000 ] || [ $FUNCTIONS_DIFF -gt 10000 ] || [ $ARRAYS_DIFF -gt 20000 ]; then
            LEAK_DETECTED=true
            LEAK_SEVERITY="critical"
            LEAK_TYPES+=("general objects")
        elif [ $PROMISES_DIFF -gt 1000 ] || [ $FUNCTIONS_DIFF -gt 5000 ] || [ $ARRAYS_DIFF -gt 10000 ]; then
            LEAK_DETECTED=true
            if [ "$LEAK_SEVERITY" != "critical" ]; then
                LEAK_SEVERITY="moderate"
            fi
            LEAK_TYPES+=("general objects")
        fi
    fi
    
    # Report findings
    if [ "$LEAK_DETECTED" = true ]; then
        if [ "$LEAK_SEVERITY" = "critical" ]; then
            echo -e "${RED}🚨 CRITICAL MEMORY LEAK DETECTED IN BUN-IN-NODE CONTAINER!${NC}"
            echo "Significant object count increases detected in: ${LEAK_TYPES[*]}"
            echo "This confirms the leak is in Bun runtime, not containerization!"
        else
            echo -e "${YELLOW}⚠️  MODERATE MEMORY LEAK DETECTED IN BUN-IN-NODE CONTAINER${NC}"
            echo "Some objects are not being garbage collected properly in: ${LEAK_TYPES[*]}"
            echo "Monitor for continued growth over time."
        fi
    else
        echo -e "${GREEN}✅ No significant memory leak detected in Bun-in-Node container${NC}"
        echo "Object counts remained relatively stable across all monitored types."
    fi
fi

# Wait and check for continued growth
echo -e "${BLUE}⏳ Waiting 2 minutes to check for continued growth...${NC}"
sleep 120

echo -e "${BLUE}📊 Getting delayed memory statistics...${NC}"
echo "Delayed Check HTTP Objects:"
DELAYED=$(get_memory_stats)
echo "$DELAYED"
echo ""

if $JQ_AVAILABLE; then
    DELAYED_HEADERS=$(echo "$DELAYED" | jq -r '.Headers')
    DELAYED_RESPONSES=$(echo "$DELAYED" | jq -r '.NodeHTTPResponse')
    DELAYED_ARGUMENTS=$(echo "$DELAYED" | jq -r '.Arguments')
    DELAYED_SOCKETS=$(echo "$DELAYED" | jq -r '.NodeHTTPServerSocket')
    
    DELAYED_HEADERS_DIFF=$((DELAYED_HEADERS - POST_HEADERS))
    DELAYED_RESPONSES_DIFF=$((DELAYED_RESPONSES - POST_RESPONSES))
    DELAYED_ARGUMENTS_DIFF=$((DELAYED_ARGUMENTS - POST_ARGUMENTS))
    DELAYED_SOCKETS_DIFF=$((DELAYED_SOCKETS - POST_SOCKETS))
    
    echo -e "${BLUE}📈 Continued Growth Analysis (HTTP Objects):${NC}"
    echo "Headers: $POST_HEADERS → $DELAYED_HEADERS (+$DELAYED_HEADERS_DIFF)"
    echo "NodeHTTPResponse: $POST_RESPONSES → $DELAYED_RESPONSES (+$DELAYED_RESPONSES_DIFF)"
    echo "Arguments: $POST_ARGUMENTS → $DELAYED_ARGUMENTS (+$DELAYED_ARGUMENTS_DIFF)"
    echo "NodeHTTPServerSocket: $POST_SOCKETS → $DELAYED_SOCKETS (+$DELAYED_SOCKETS_DIFF)"
    echo ""
    
    # Check continued growth in general objects if available
    if [ "$TRACK_OBJECTS" = true ] && [ -n "$POST_PROMISES" ]; then
        DELAYED_ALL=$(get_all_object_counts)
        if [ "$DELAYED_ALL" != "null" ] && [ -n "$DELAYED_ALL" ]; then
            DELAYED_PROMISES=$(echo "$DELAYED_ALL" | jq -r '.Promise // 0')
            DELAYED_ARRAYS=$(echo "$DELAYED_ALL" | jq -r '.Array // 0')
            DELAYED_FUNCTIONS=$(echo "$DELAYED_ALL" | jq -r '.Function // 0')
            
            DELAYED_PROMISES_DIFF=$((DELAYED_PROMISES - POST_PROMISES))
            DELAYED_ARRAYS_DIFF=$((DELAYED_ARRAYS - POST_ARRAYS))
            DELAYED_FUNCTIONS_DIFF=$((DELAYED_FUNCTIONS - POST_FUNCTIONS))
            
            echo -e "${BLUE}📈 Continued Growth Analysis (General Objects):${NC}"
            echo "Promises: $POST_PROMISES → $DELAYED_PROMISES (+$DELAYED_PROMISES_DIFF)"
            echo "Arrays: $POST_ARRAYS → $DELAYED_ARRAYS (+$DELAYED_ARRAYS_DIFF)"
            echo "Functions: $POST_FUNCTIONS → $DELAYED_FUNCTIONS (+$DELAYED_FUNCTIONS_DIFF)"
            echo ""
        fi
    fi
    
    # Analyze continued growth severity
    CONTINUED_GROWTH=false
    GROWTH_TYPES=()
    
    # Check HTTP objects for continued growth
    if [ $DELAYED_HEADERS_DIFF -gt 10 ] || [ $DELAYED_RESPONSES_DIFF -gt 10 ] || [ $DELAYED_SOCKETS_DIFF -gt 5 ]; then
        CONTINUED_GROWTH=true
        GROWTH_TYPES+=("HTTP objects")
    fi
    
    # Check general objects for continued growth if available
    if [ "$TRACK_OBJECTS" = true ] && [ -n "$DELAYED_PROMISES_DIFF" ]; then
        if [ $DELAYED_PROMISES_DIFF -gt 100 ] || [ $DELAYED_ARRAYS_DIFF -gt 500 ] || [ $DELAYED_FUNCTIONS_DIFF -gt 1000 ]; then
            CONTINUED_GROWTH=true
            GROWTH_TYPES+=("general objects")
        fi
    fi
    
    if [ "$CONTINUED_GROWTH" = true ]; then
        echo -e "${RED}🚨 OBJECTS CONTINUE TO GROW WITHOUT REQUESTS IN BUN-IN-NODE!${NC}"
        echo "Continued growth detected in: ${GROWTH_TYPES[*]}"
        echo "This indicates ongoing background activity or a severe Bun runtime leak."
    else
        echo -e "${GREEN}✅ Object growth has stabilized in Bun-in-Node container${NC}"
        echo "No significant continued growth detected across all monitored object types."
    fi
fi

# Show container logs for debugging
echo -e "${BLUE}📋 Container logs (last 20 lines):${NC}"
docker logs --tail 20 $CONTAINER_ID

echo -e "${GREEN}✅ Bun-in-Node.js test completed!${NC}"
echo ""
echo -e "${BLUE}📋 Bun-in-Node.js Test Summary:${NC}"
echo "Duration: $DURATION seconds"
echo "Base Container: Node.js 24.0.2-slim"
echo "Runtime: Bun (installed inside Node.js container)"
echo "Container: node-bun-memory-leak-repro"
if $JQ_AVAILABLE; then
    echo "Memory growth: RSS +${RSS_DIFF}MB, HeapUsed +${HEAP_USED_DIFF}MB"
    echo "HTTP Objects leak: +$HEADERS_DIFF Headers, +$RESPONSES_DIFF NodeHTTPResponse, +$SOCKETS_DIFF Sockets"
    if [ "$TRACK_OBJECTS" = true ] && [ -n "$PROMISES_DIFF" ]; then
        echo "General Objects leak: +$PROMISES_DIFF Promises, +$ARRAYS_DIFF Arrays, +$FUNCTIONS_DIFF Functions"
    fi
    echo "Leak severity: $LEAK_SEVERITY"
fi
echo ""
echo -e "${BLUE}🔬 Isolation Test Results:${NC}"
echo "This test isolates whether memory leaks are due to:"
echo "- Bun runtime itself (if leaks occur here)"
echo "- Bun's Docker image environment (if no leaks occur here)"
echo ""
echo -e "${GREEN}✅ Compare with other test results for comprehensive analysis!${NC}" 