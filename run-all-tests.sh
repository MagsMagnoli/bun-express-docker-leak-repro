#!/bin/bash

# Master Test Runner - Runs both Local and Docker memory leak tests
# This script runs both test variants and provides a comparison summary

set -e

echo "🧪 Bun + Express Memory Leak Test Suite"
echo "========================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check dependencies
echo -e "${BLUE}🔍 Checking dependencies...${NC}"

MISSING_DEPS=()

if ! command -v bun &> /dev/null; then
    MISSING_DEPS+=("bun")
fi

if ! command -v docker &> /dev/null; then
    MISSING_DEPS+=("docker")
fi

if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}⚠️  jq is not installed. JSON output will not be formatted.${NC}"
fi

if [ ${#MISSING_DEPS[@]} -ne 0 ]; then
    echo -e "${RED}❌ Missing required dependencies: ${MISSING_DEPS[*]}${NC}"
    echo "Please install the missing dependencies and try again."
    exit 1
fi

echo -e "${GREEN}✅ All dependencies available${NC}"
echo ""

# Function to extract key metrics from test output
extract_metrics() {
    local output="$1"
    local env="$2"
    
    # Extract duration
    local duration=$(echo "$output" | grep "Duration:" | sed 's/.*Duration: \([0-9]*\) seconds.*/\1/')
    
    # Extract leak metrics if available
    local headers_leak=$(echo "$output" | grep "HTTP Objects leak:" | sed 's/.*+\([0-9]*\) Headers.*/\1/' || echo "N/A")
    local responses_leak=$(echo "$output" | grep "HTTP Objects leak:" | sed 's/.*+\([0-9]*\) NodeHTTPResponse.*/\1/' || echo "N/A")
    local severity=$(echo "$output" | grep "Leak severity:" | sed 's/.*Leak severity: \([a-z]*\).*/\1/' || echo "none")
    
    echo "Environment: $env"
    echo "Duration: ${duration}s"
    echo "Headers leak: +$headers_leak"
    echo "Responses leak: +$responses_leak"
    echo "Severity: $severity"
    echo ""
}

# Test selection
if [ "$1" = "--local-only" ]; then
    RUN_LOCAL=true
    RUN_DOCKER=false
    echo -e "${CYAN}🎯 Running LOCAL test only${NC}"
    echo -e "${YELLOW}⏱️  Estimated time: ~3-5 minutes${NC}"
elif [ "$1" = "--docker-only" ]; then
    RUN_LOCAL=false
    RUN_DOCKER=true
    echo -e "${CYAN}🎯 Running DOCKER test only${NC}"
    echo -e "${YELLOW}⏱️  Estimated time: ~3-5 minutes${NC}"
else
    RUN_LOCAL=true
    RUN_DOCKER=true
    echo -e "${CYAN}🎯 Running BOTH local and Docker tests${NC}"
    echo -e "${YELLOW}⏱️  Estimated time: ~6-10 minutes total${NC}"
fi

echo ""
echo -e "${BLUE}📋 What will happen:${NC}"
if [ "$RUN_LOCAL" = true ]; then
    echo "  1. 🏠 Local Bun test (install deps → start server → 1000 requests → 2min wait → analysis)"
fi
if [ "$RUN_DOCKER" = true ]; then
    echo "  2. 🐳 Docker test (build image → start container → 1000 requests → 2min wait → analysis)"
fi
echo "  3. 📊 Comparison summary and metrics extraction"
echo ""

# Run Local Test
if [ "$RUN_LOCAL" = true ]; then
    echo -e "${BLUE}🏠 Starting LOCAL Bun test...${NC}"
    echo "================================================"
    
    if [ -f "test-reproduction-local.sh" ]; then
        chmod +x test-reproduction-local.sh
        echo -e "${YELLOW}⏳ Running local test (this will take ~3-5 minutes)...${NC}"
        echo ""
        
        # Run test with live output and capture for metrics
        ./test-reproduction-local.sh 2>&1 | tee /tmp/local_test_output.log
        LOCAL_EXIT_CODE=${PIPESTATUS[0]}
        LOCAL_OUTPUT=$(cat /tmp/local_test_output.log)
        
        echo ""
        if [ $LOCAL_EXIT_CODE -eq 0 ]; then
            echo -e "${GREEN}✅ Local test completed successfully${NC}"
        else
            echo -e "${RED}❌ Local test failed with exit code $LOCAL_EXIT_CODE${NC}"
        fi
        
        echo ""
        echo -e "${BLUE}📊 Local Test Metrics:${NC}"
        extract_metrics "$LOCAL_OUTPUT" "Local Bun"
        
        # Cleanup temp file
        rm -f /tmp/local_test_output.log
    else
        echo -e "${RED}❌ test-reproduction-local.sh not found${NC}"
        LOCAL_EXIT_CODE=1
    fi
    
    echo "================================================"
    echo ""
fi

# Run Docker Test
if [ "$RUN_DOCKER" = true ]; then
    echo -e "${BLUE}🐳 Starting DOCKER test...${NC}"
    echo "================================================"
    
    if [ -f "test-reproduction.sh" ]; then
        chmod +x test-reproduction.sh
        echo -e "${YELLOW}⏳ Running Docker test (this will take ~3-5 minutes)...${NC}"
        echo ""
        
        # Run test with live output and capture for metrics
        ./test-reproduction.sh 2>&1 | tee /tmp/docker_test_output.log
        DOCKER_EXIT_CODE=${PIPESTATUS[0]}
        DOCKER_OUTPUT=$(cat /tmp/docker_test_output.log)
        
        echo ""
        if [ $DOCKER_EXIT_CODE -eq 0 ]; then
            echo -e "${GREEN}✅ Docker test completed successfully${NC}"
        else
            echo -e "${RED}❌ Docker test failed with exit code $DOCKER_EXIT_CODE${NC}"
        fi
        
        echo ""
        echo -e "${BLUE}📊 Docker Test Metrics:${NC}"
        extract_metrics "$DOCKER_OUTPUT" "Docker Container"
        
        # Cleanup temp file
        rm -f /tmp/docker_test_output.log
    else
        echo -e "${RED}❌ test-reproduction.sh not found${NC}"
        DOCKER_EXIT_CODE=1
    fi
    
    echo "================================================"
    echo ""
fi

# Summary
echo -e "${CYAN}📋 TEST SUITE SUMMARY${NC}"
echo "===================="

if [ "$RUN_LOCAL" = true ] && [ "$RUN_DOCKER" = true ]; then
    if [ $LOCAL_EXIT_CODE -eq 0 ] && [ $DOCKER_EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}✅ Both tests completed successfully${NC}"
        echo ""
        echo -e "${BLUE}🔍 Comparison Analysis:${NC}"
        echo "- Both environments can be tested for memory leak patterns"
        echo "- Compare the leak rates and severity between local and Docker"
        echo "- Look for consistency in memory leak behavior"
        echo "- Docker provides isolation, local provides direct access"
    elif [ $LOCAL_EXIT_CODE -eq 0 ]; then
        echo -e "${YELLOW}⚠️  Local test passed, Docker test failed${NC}"
        echo "- Local Bun execution works correctly"
        echo "- Docker environment may have configuration issues"
    elif [ $DOCKER_EXIT_CODE -eq 0 ]; then
        echo -e "${YELLOW}⚠️  Docker test passed, Local test failed${NC}"
        echo "- Docker environment works correctly"
        echo "- Local Bun installation may have issues"
    else
        echo -e "${RED}❌ Both tests failed${NC}"
        echo "- Check Bun installation and dependencies"
        echo "- Verify Docker is running and accessible"
    fi
elif [ "$RUN_LOCAL" = true ]; then
    if [ $LOCAL_EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}✅ Local test completed successfully${NC}"
    else
        echo -e "${RED}❌ Local test failed${NC}"
    fi
elif [ "$RUN_DOCKER" = true ]; then
    if [ $DOCKER_EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}✅ Docker test completed successfully${NC}"
    else
        echo -e "${RED}❌ Docker test failed${NC}"
    fi
fi

echo ""
echo -e "${BLUE}📖 Usage:${NC}"
echo "  ./run-all-tests.sh           # Run both tests"
echo "  ./run-all-tests.sh --local-only   # Run only local test"
echo "  ./run-all-tests.sh --docker-only  # Run only Docker test"
echo ""
echo "Share results with the Bun development team for comprehensive analysis." 