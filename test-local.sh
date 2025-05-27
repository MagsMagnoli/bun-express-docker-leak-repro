#!/bin/bash

# Bun + Express Memory Leak Reproduction Test Script (Local Version)
# This script automates the reproduction steps using local Bun for easy testing

set -e

echo "🔬 Bun + Express Memory Leak Reproduction Test (Local)"
echo "===================================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if bun is installed
if ! command -v bun &> /dev/null; then
    echo -e "${RED}❌ Bun is not installed. Please install Bun first.${NC}"
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
echo "Bun version: $(bun --version)"
echo "OS: $(uname -s) $(uname -r)"
echo "Date: $(date)"
echo ""

# Install dependencies
echo -e "${BLUE}📦 Installing dependencies...${NC}"
bun install

# Start server in background
echo -e "${BLUE}🚀 Starting local Bun server...${NC}"
bun run index.ts &
SERVER_PID=$!

# Function to cleanup server
cleanup_server() {
    echo -e "${BLUE}🧹 Cleaning up local server...${NC}"
    kill $SERVER_PID 2>/dev/null || true
    wait $SERVER_PID 2>/dev/null || true
}

# Set trap to cleanup on exit
trap cleanup_server EXIT

# Wait for server to start
echo -e "${YELLOW}⏳ Waiting for server to start...${NC}"
sleep 3

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
    echo "Server output (if any):"
    jobs -l
    exit 1
fi

echo -e "${GREEN}✅ Local Bun server is running and ready${NC}"

# Show process info
echo -e "${BLUE}📦 Process Information:${NC}"
echo "Server PID: $SERVER_PID"
echo "Environment: Local Bun execution"
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

# Function to get top object types
get_top_objects() {
    if $JQ_AVAILABLE; then
        curl -s http://localhost:3000/memory | jq '.heap.analysis.topObjectTypes'
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
    if [ -n "$BASELINE_PROMISES" ]; then
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
    if [ -n "$PROMISES_DIFF" ]; then
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
    if [ -n "$PROMISES_DIFF" ]; then
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
            echo -e "${RED}🚨 CRITICAL MEMORY LEAK DETECTED!${NC}"
            echo "Significant object count increases detected in: ${LEAK_TYPES[*]}"
            echo "This confirms a serious memory leak issue."
        else
            echo -e "${YELLOW}⚠️  MODERATE MEMORY LEAK DETECTED${NC}"
            echo "Some objects are not being garbage collected properly in: ${LEAK_TYPES[*]}"
            echo "Monitor for continued growth over time."
        fi
    else
        echo -e "${GREEN}✅ No significant memory leak detected${NC}"
        echo "Object counts remained relatively stable across all monitored types."
    fi
fi

# Wait and check again
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
    if [ -n "$POST_PROMISES" ]; then
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
    if [ -n "$DELAYED_PROMISES_DIFF" ]; then
        if [ $DELAYED_PROMISES_DIFF -gt 100 ] || [ $DELAYED_ARRAYS_DIFF -gt 500 ] || [ $DELAYED_FUNCTIONS_DIFF -gt 1000 ]; then
            CONTINUED_GROWTH=true
            GROWTH_TYPES+=("general objects")
        fi
    fi
    
    if [ "$CONTINUED_GROWTH" = true ]; then
        echo -e "${RED}🚨 OBJECTS CONTINUE TO GROW WITHOUT REQUESTS!${NC}"
        echo "Continued growth detected in: ${GROWTH_TYPES[*]}"
        echo "This indicates ongoing background activity or a severe leak."
    else
        echo -e "${GREEN}✅ Object growth has stabilized${NC}"
        echo "No significant continued growth detected across all monitored object types."
    fi
fi

echo -e "${GREEN}✅ Test completed!${NC}"
echo ""
echo -e "${BLUE}📋 Summary:${NC}"
echo "- Environment: Local Bun execution"
echo "- Load test: 1000 requests completed"
echo "- Duration: ${DURATION} seconds"
if $JQ_AVAILABLE; then
    echo "- Memory growth: RSS +${RSS_DIFF}MB, HeapUsed +${HEAP_USED_DIFF}MB"
    echo "- HTTP Objects leak: +$HEADERS_DIFF Headers, +$RESPONSES_DIFF NodeHTTPResponse, +$SOCKETS_DIFF Sockets"
    echo "- Leak rates: Headers ~$HEADERS_LEAK_RATE, Responses ~$RESPONSES_LEAK_RATE per request"
    if [ -n "$PROMISES_DIFF" ]; then
        echo "- General Objects leak: +$PROMISES_DIFF Promises, +$ARRAYS_DIFF Arrays, +$FUNCTIONS_DIFF Functions"
    fi
    if [ "$LEAK_DETECTED" = true ]; then
        echo "- Leak severity: $LEAK_SEVERITY in ${LEAK_TYPES[*]}"
    fi
fi
echo ""
echo "Please share these results with the Bun development team." 