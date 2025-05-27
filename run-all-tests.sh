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
    
    # Extract leak metrics if available (try both formats)
    local headers_leak=$(echo "$output" | grep "HTTP Objects leak:" | sed 's/.*+\([0-9]*\) Headers.*/\1/' 2>/dev/null || echo "N/A")
    local responses_leak=$(echo "$output" | grep "HTTP Objects leak:" | sed 's/.*+\([0-9]*\) NodeHTTPResponse.*/\1/' 2>/dev/null || echo "N/A")
    
    # For Node.js, also try to extract memory growth
    local memory_growth=$(echo "$output" | grep "Memory growth:" | sed 's/.*RSS +\([0-9]*\)MB.*/\1/' 2>/dev/null || echo "N/A")
    
    local severity=$(echo "$output" | grep "Leak severity:" | sed 's/.*Leak severity: \([a-z]*\).*/\1/' || echo "none")
    
    echo "Environment: $env"
    echo "Duration: ${duration}s"
    if [ "$headers_leak" != "N/A" ] && [ "$responses_leak" != "N/A" ]; then
        echo "Headers leak: +$headers_leak"
        echo "Responses leak: +$responses_leak"
    fi
    if [ "$memory_growth" != "N/A" ]; then
        echo "Memory growth: +${memory_growth}MB RSS"
    fi
    echo "Severity: $severity"
    echo ""
}

# Test selection
if [ "$1" = "--local-only" ]; then
    RUN_LOCAL=true
    RUN_DOCKER=false
    RUN_NODE=false
    RUN_NODE_BUN=false
    echo -e "${CYAN}🎯 Running LOCAL test only${NC}"
    echo -e "${YELLOW}⏱️  Estimated time: ~3-5 minutes${NC}"
elif [ "$1" = "--docker-only" ]; then
    RUN_LOCAL=false
    RUN_DOCKER=true
    RUN_NODE=false
    RUN_NODE_BUN=false
    echo -e "${CYAN}🎯 Running DOCKER test only${NC}"
    echo -e "${YELLOW}⏱️  Estimated time: ~3-5 minutes${NC}"
elif [ "$1" = "--node-only" ]; then
    RUN_LOCAL=false
    RUN_DOCKER=false
    RUN_NODE=true
    RUN_NODE_BUN=false
    echo -e "${CYAN}🎯 Running NODE.JS test only${NC}"
    echo -e "${YELLOW}⏱️  Estimated time: ~3-5 minutes${NC}"
elif [ "$1" = "--node-bun-only" ]; then
    RUN_LOCAL=false
    RUN_DOCKER=false
    RUN_NODE=false
    RUN_NODE_BUN=true
    echo -e "${CYAN}🎯 Running BUN-IN-NODE.JS test only${NC}"
    echo -e "${YELLOW}⏱️  Estimated time: ~3-5 minutes${NC}"
else
    RUN_LOCAL=true
    RUN_DOCKER=true
    RUN_NODE=true
    RUN_NODE_BUN=true
    echo -e "${CYAN}🎯 Running ALL tests (Local Bun + Docker Bun + Node.js + Bun-in-Node)${NC}"
    echo -e "${YELLOW}⏱️  Estimated time: ~12-20 minutes total${NC}"
fi

echo ""
echo -e "${BLUE}📋 What will happen:${NC}"
if [ "$RUN_LOCAL" = true ]; then
    echo "  1. 🏠 Local Bun test (install deps → start server → 1000 requests → 2min wait → analysis)"
fi
if [ "$RUN_DOCKER" = true ]; then
    echo "  2. 🐳 Docker Bun test (build image → start container → 1000 requests → 2min wait → analysis)"
fi
if [ "$RUN_NODE" = true ]; then
    echo "  3. 🟢 Node.js Docker test (build image → start container → 1000 requests → 2min wait → analysis)"
fi
if [ "$RUN_NODE_BUN" = true ]; then
    echo "  4. 🔬 Bun-in-Node.js test (build hybrid image → start container → 1000 requests → 2min wait → analysis)"
fi
echo "  5. 📊 Comparison summary and metrics extraction"
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

# Run Node.js Docker Test
if [ "$RUN_NODE" = true ]; then
    echo -e "${BLUE}🟢 Starting NODE.JS Docker test...${NC}"
    echo "================================================"
    
    if [ -f "test-docker-node.sh" ]; then
        chmod +x test-docker-node.sh
        echo -e "${YELLOW}⏳ Running Node.js Docker test (this will take ~3-5 minutes)...${NC}"
        echo ""
        
        # Run test with live output and capture for metrics
        ./test-docker-node.sh 2>&1 | tee /tmp/node_test_output.log
        NODE_EXIT_CODE=${PIPESTATUS[0]}
        NODE_OUTPUT=$(cat /tmp/node_test_output.log)
        
        echo ""
        if [ $NODE_EXIT_CODE -eq 0 ]; then
            echo -e "${GREEN}✅ Node.js Docker test completed successfully${NC}"
        else
            echo -e "${RED}❌ Node.js Docker test failed with exit code $NODE_EXIT_CODE${NC}"
        fi
        
        echo ""
        echo -e "${BLUE}📊 Node.js Docker Test Metrics:${NC}"
        extract_metrics "$NODE_OUTPUT" "Node.js 24.0.2 Docker"
        
        # Cleanup temp file
        rm -f /tmp/node_test_output.log
    else
        echo -e "${RED}❌ test-docker-node.sh not found${NC}"
        NODE_EXIT_CODE=1
    fi
    
    echo "================================================"
    echo ""
fi

# Run Node-Bun Docker Test
if [ "$RUN_NODE_BUN" = true ]; then
    echo -e "${BLUE}🔬 Starting BUN-IN-NODE.JS Docker test...${NC}"
    echo "================================================"
    
    if [ -f "test-docker-node-bun.sh" ]; then
        chmod +x test-docker-node-bun.sh
        echo -e "${YELLOW}⏳ Running Bun-in-Node.js Docker test (this will take ~3-5 minutes)...${NC}"
        echo ""
        
        # Run test with live output and capture for metrics
        ./test-docker-node-bun.sh 2>&1 | tee /tmp/node_bun_test_output.log
        NODE_BUN_EXIT_CODE=${PIPESTATUS[0]}
        NODE_BUN_OUTPUT=$(cat /tmp/node_bun_test_output.log)
        
        echo ""
        if [ $NODE_BUN_EXIT_CODE -eq 0 ]; then
            echo -e "${GREEN}✅ Bun-in-Node.js Docker test completed successfully${NC}"
        else
            echo -e "${RED}❌ Bun-in-Node.js Docker test failed with exit code $NODE_BUN_EXIT_CODE${NC}"
        fi
        
        echo ""
        echo -e "${BLUE}📊 Bun-in-Node.js Docker Test Metrics:${NC}"
        extract_metrics "$NODE_BUN_OUTPUT" "Bun-in-Node.js Docker"
        
        # Cleanup temp file
        rm -f /tmp/node_bun_test_output.log
    else
        echo -e "${RED}❌ test-docker-node-bun.sh not found${NC}"
        NODE_BUN_EXIT_CODE=1
    fi
    
    echo "================================================"
    echo ""
fi

# Summary
echo -e "${CYAN}📋 TEST SUITE SUMMARY${NC}"
echo "===================="

# Count successful tests
SUCCESSFUL_TESTS=0
TOTAL_TESTS=0

if [ "$RUN_LOCAL" = true ]; then
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [ $LOCAL_EXIT_CODE -eq 0 ]; then
        SUCCESSFUL_TESTS=$((SUCCESSFUL_TESTS + 1))
    fi
fi

if [ "$RUN_DOCKER" = true ]; then
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [ $DOCKER_EXIT_CODE -eq 0 ]; then
        SUCCESSFUL_TESTS=$((SUCCESSFUL_TESTS + 1))
    fi
fi

if [ "$RUN_NODE" = true ]; then
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [ $NODE_EXIT_CODE -eq 0 ]; then
        SUCCESSFUL_TESTS=$((SUCCESSFUL_TESTS + 1))
    fi
fi

if [ "$RUN_NODE_BUN" = true ]; then
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [ $NODE_BUN_EXIT_CODE -eq 0 ]; then
        SUCCESSFUL_TESTS=$((SUCCESSFUL_TESTS + 1))
    fi
fi

echo -e "${BLUE}📊 Test Results: $SUCCESSFUL_TESTS/$TOTAL_TESTS tests passed${NC}"
echo ""

if [ $SUCCESSFUL_TESTS -eq $TOTAL_TESTS ] && [ $TOTAL_TESTS -gt 0 ]; then
    echo -e "${GREEN}✅ All tests completed successfully${NC}"
    echo ""
    echo -e "${BLUE}🔍 Comparison Analysis:${NC}"
    if [ "$RUN_LOCAL" = true ] && [ "$RUN_DOCKER" = true ] && [ "$RUN_NODE" = true ] && [ "$RUN_NODE_BUN" = true ]; then
        echo "- Compare memory leak patterns across all FOUR environments:"
        echo "  • Local Bun: Direct execution, no containerization"
        echo "  • Docker Bun: Containerized Bun environment (official Bun image)"
        echo "  • Node.js 24.0.2: Native TypeScript support with --experimental-strip-types"
        echo "  • Bun-in-Node: Bun runtime inside Node.js container (isolation test)"
        echo "- Critical analysis: If Bun-in-Node shows leaks, it's a Bun runtime issue"
        echo "- If Bun-in-Node is clean, the issue may be Bun's Docker environment"
        echo "- Node.js should show proper garbage collection (control group)"
    elif [ "$RUN_LOCAL" = true ] && [ "$RUN_DOCKER" = true ] && [ "$RUN_NODE_BUN" = true ]; then
        echo "- Compare Bun runtime across different environments:"
        echo "  • Local Bun vs Docker Bun vs Bun-in-Node"
        echo "- Isolate whether leaks are runtime or environment specific"
    elif [ "$RUN_NODE" = true ] && [ "$RUN_NODE_BUN" = true ]; then
        echo "- Compare Node.js vs Bun runtime in same container environment"
        echo "- Perfect isolation test for runtime-specific issues"
    elif [ "$RUN_NODE_BUN" = true ]; then
        echo "- Bun-in-Node.js isolation test completed"
        echo "- This isolates Bun runtime behavior from containerization effects"
    elif [ "$RUN_LOCAL" = true ] && [ "$RUN_DOCKER" = true ]; then
        echo "- Both Bun environments can be tested for memory leak patterns"
        echo "- Compare the leak rates and severity between local and Docker"
        echo "- Look for consistency in memory leak behavior"
    elif [ "$RUN_NODE" = true ]; then
        echo "- Node.js 24.0.2 with experimental TypeScript support tested"
        echo "- Should demonstrate proper memory management (no leaks)"
        echo "- Use as baseline for comparison with Bun results"
    fi
elif [ $SUCCESSFUL_TESTS -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Partial success: $SUCCESSFUL_TESTS/$TOTAL_TESTS tests passed${NC}"
    echo ""
    if [ "$RUN_LOCAL" = true ] && [ $LOCAL_EXIT_CODE -ne 0 ]; then
        echo "- Local Bun test failed - check Bun installation"
    fi
    if [ "$RUN_DOCKER" = true ] && [ $DOCKER_EXIT_CODE -ne 0 ]; then
        echo "- Docker Bun test failed - check Docker configuration"
    fi
    if [ "$RUN_NODE" = true ] && [ $NODE_EXIT_CODE -ne 0 ]; then
        echo "- Node.js Docker test failed - check Node.js setup"
    fi
    if [ "$RUN_NODE_BUN" = true ] && [ $NODE_BUN_EXIT_CODE -ne 0 ]; then
        echo "- Bun-in-Node.js Docker test failed - check hybrid setup"
    fi
else
    echo -e "${RED}❌ All tests failed${NC}"
    echo "- Check dependencies: Bun, Docker, Node.js"
    echo "- Verify Docker is running and accessible"
    echo "- Check file permissions on test scripts"
fi

echo ""
echo -e "${BLUE}📖 Usage:${NC}"
echo "  ./run-all-tests.sh                  # Run all tests (Local Bun + Docker Bun + Node.js + Bun-in-Node)"
echo "  ./run-all-tests.sh --local-only     # Run only local Bun test"
echo "  ./run-all-tests.sh --docker-only    # Run only Docker Bun test"
echo "  ./run-all-tests.sh --node-only      # Run only Node.js Docker test"
echo "  ./run-all-tests.sh --node-bun-only  # Run only Bun-in-Node.js isolation test"
echo ""
echo "Share results with the Bun development team for comprehensive analysis." 