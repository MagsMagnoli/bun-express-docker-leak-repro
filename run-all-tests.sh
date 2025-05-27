#!/bin/bash

# Comprehensive Container Test Runner for Bun Memory Leak Reproduction
# Tests Bun across 7 different environments to isolate containerization effects

set -e

echo "🧪 Bun Memory Leak - Comprehensive Container Test Matrix"
echo "========================================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Parse command line arguments
LOCAL_ONLY=false
DOCKER_ONLY=false
NODE_ONLY=false
NODE_BUN_ONLY=false
UBUNTU_BUN_ONLY=false
DEBIAN_BUN_ONLY=false
ALPINE_BUN_ONLY=false

for arg in "$@"; do
    case $arg in
        --local-only)
            LOCAL_ONLY=true
            shift
            ;;
        --docker-only)
            DOCKER_ONLY=true
            shift
            ;;
        --node-only)
            NODE_ONLY=true
            shift
            ;;
        --node-bun-only)
            NODE_BUN_ONLY=true
            shift
            ;;
        --ubuntu-bun-only)
            UBUNTU_BUN_ONLY=true
            shift
            ;;
        --debian-bun-only)
            DEBIAN_BUN_ONLY=true
            shift
            ;;
        --alpine-bun-only)
            ALPINE_BUN_ONLY=true
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "🔬 Comprehensive Container Test Matrix:"
            echo ""
            echo "Options:"
            echo "  --local-only      Run only local Bun test (no container)"
            echo "  --docker-only     Run only Docker Bun test (official Bun image)"
            echo "  --node-only       Run only Node.js Docker test (control group)"
            echo "  --node-bun-only   Run only Bun-in-Node Docker test (isolation)"
            echo "  --ubuntu-bun-only Run only Ubuntu + Bun Docker test"
            echo "  --debian-bun-only Run only Debian + Bun Docker test"
            echo "  --alpine-bun-only Run only Alpine + Bun Docker test"
            echo "  --help            Show this help message"
            echo ""
            echo "🎯 Test Matrix Analysis:"
            echo "  Local Bun:     No container - baseline behavior"
            echo "  Docker Bun:    Official Bun container"
            echo "  Node.js:       Control group - should be clean"
            echo "  Bun-in-Node:   Isolation test - Bun runtime in Node container"
            echo "  Ubuntu + Bun:  Test Ubuntu-specific containerization effects"
            echo "  Debian + Bun:  Test Debian-specific containerization effects"
            echo "  Alpine + Bun:  Test minimal Linux containerization effects"
            echo ""
            echo "By default, all tests are run in sequence (~25-35 minutes total)."
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

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

# Determine which tests to run
if [ "$LOCAL_ONLY" = true ]; then
    RUN_LOCAL=true
    RUN_DOCKER=false
    RUN_NODE=false
    RUN_NODE_BUN=false
    RUN_UBUNTU_BUN=false
    RUN_DEBIAN_BUN=false
    RUN_ALPINE_BUN=false
    echo -e "${CYAN}🎯 Running LOCAL test only${NC}"
    echo -e "${YELLOW}⏱️  Estimated time: ~3-5 minutes${NC}"
elif [ "$DOCKER_ONLY" = true ]; then
    RUN_LOCAL=false
    RUN_DOCKER=true
    RUN_NODE=false
    RUN_NODE_BUN=false
    RUN_UBUNTU_BUN=false
    RUN_DEBIAN_BUN=false
    RUN_ALPINE_BUN=false
    echo -e "${CYAN}🎯 Running DOCKER BUN test only${NC}"
    echo -e "${YELLOW}⏱️  Estimated time: ~3-5 minutes${NC}"
elif [ "$NODE_ONLY" = true ]; then
    RUN_LOCAL=false
    RUN_DOCKER=false
    RUN_NODE=true
    RUN_NODE_BUN=false
    RUN_UBUNTU_BUN=false
    RUN_DEBIAN_BUN=false
    RUN_ALPINE_BUN=false
    echo -e "${CYAN}🎯 Running NODE.JS test only${NC}"
    echo -e "${YELLOW}⏱️  Estimated time: ~3-5 minutes${NC}"
elif [ "$NODE_BUN_ONLY" = true ]; then
    RUN_LOCAL=false
    RUN_DOCKER=false
    RUN_NODE=false
    RUN_NODE_BUN=true
    RUN_UBUNTU_BUN=false
    RUN_DEBIAN_BUN=false
    RUN_ALPINE_BUN=false
    echo -e "${CYAN}🎯 Running BUN-IN-NODE.JS test only${NC}"
    echo -e "${YELLOW}⏱️  Estimated time: ~3-5 minutes${NC}"
elif [ "$UBUNTU_BUN_ONLY" = true ]; then
    RUN_LOCAL=false
    RUN_DOCKER=false
    RUN_NODE=false
    RUN_NODE_BUN=false
    RUN_UBUNTU_BUN=true
    RUN_DEBIAN_BUN=false
    RUN_ALPINE_BUN=false
    echo -e "${CYAN}🎯 Running UBUNTU + BUN test only${NC}"
    echo -e "${YELLOW}⏱️  Estimated time: ~3-5 minutes${NC}"
elif [ "$DEBIAN_BUN_ONLY" = true ]; then
    RUN_LOCAL=false
    RUN_DOCKER=false
    RUN_NODE=false
    RUN_NODE_BUN=false
    RUN_UBUNTU_BUN=false
    RUN_DEBIAN_BUN=true
    RUN_ALPINE_BUN=false
    echo -e "${CYAN}🎯 Running DEBIAN + BUN test only${NC}"
    echo -e "${YELLOW}⏱️  Estimated time: ~3-5 minutes${NC}"
elif [ "$ALPINE_BUN_ONLY" = true ]; then
    RUN_LOCAL=false
    RUN_DOCKER=false
    RUN_NODE=false
    RUN_NODE_BUN=false
    RUN_UBUNTU_BUN=false
    RUN_DEBIAN_BUN=false
    RUN_ALPINE_BUN=true
    echo -e "${CYAN}🎯 Running ALPINE + BUN test only${NC}"
    echo -e "${YELLOW}⏱️  Estimated time: ~3-5 minutes${NC}"
else
    RUN_LOCAL=true
    RUN_DOCKER=true
    RUN_NODE=true
    RUN_NODE_BUN=true
    RUN_UBUNTU_BUN=true
    RUN_DEBIAN_BUN=true
    RUN_ALPINE_BUN=true
    echo -e "${CYAN}🎯 Running ALL 7 tests (Comprehensive Container Matrix)${NC}"
    echo -e "${YELLOW}⏱️  Estimated time: ~25-35 minutes total${NC}"
fi

echo ""
echo -e "${BLUE}📋 Test Matrix Overview:${NC}"
if [ "$RUN_LOCAL" = true ]; then
    echo "  1. 🏠 Local Bun (no container) - baseline behavior"
fi
if [ "$RUN_DOCKER" = true ]; then
    echo "  2. 🐳 Docker Bun (official Bun image) - standard containerization"
fi
if [ "$RUN_NODE" = true ]; then
    echo "  3. 🟢 Node.js Docker (control group) - should be clean"
fi
if [ "$RUN_NODE_BUN" = true ]; then
    echo "  4. 🔬 Bun-in-Node Docker (isolation test) - runtime vs container"
fi
if [ "$RUN_UBUNTU_BUN" = true ]; then
    echo "  5. 🟠 Ubuntu + Bun Docker - Ubuntu-specific effects"
fi
if [ "$RUN_DEBIAN_BUN" = true ]; then
    echo "  6. 🔵 Debian + Bun Docker - Debian-specific effects"
fi
if [ "$RUN_ALPINE_BUN" = true ]; then
    echo "  7. ⛰️  Alpine + Bun Docker - minimal Linux effects"
fi
echo ""

# Initialize exit codes
LOCAL_EXIT_CODE=0
DOCKER_EXIT_CODE=0
NODE_EXIT_CODE=0
NODE_BUN_EXIT_CODE=0
UBUNTU_BUN_EXIT_CODE=0
DEBIAN_BUN_EXIT_CODE=0
ALPINE_BUN_EXIT_CODE=0

# Run Local Test
if [ "$RUN_LOCAL" = true ]; then
    echo -e "${BLUE}🏠 Starting LOCAL Bun test...${NC}"
    echo "================================================"
    
    if [ -f "test-local.sh" ]; then
        chmod +x test-local.sh
        echo -e "${YELLOW}⏳ Running local test (this will take ~3-5 minutes)...${NC}"
        echo ""
        
        ./test-local.sh 2>&1 | tee /tmp/local_test_output.log
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
        
        rm -f /tmp/local_test_output.log
    else
        echo -e "${RED}❌ test-local.sh not found${NC}"
        LOCAL_EXIT_CODE=1
    fi
    
    echo "================================================"
    echo ""
fi

# Run Docker Test
if [ "$RUN_DOCKER" = true ]; then
    echo -e "${BLUE}🐳 Starting DOCKER BUN test...${NC}"
    echo "================================================"
    
    if [ -f "test-docker-bun.sh" ]; then
        chmod +x test-docker-bun.sh
        echo -e "${YELLOW}⏳ Running Docker Bun test (this will take ~3-5 minutes)...${NC}"
        echo ""
        
        ./test-docker-bun.sh 2>&1 | tee /tmp/docker_test_output.log
        DOCKER_EXIT_CODE=${PIPESTATUS[0]}
        DOCKER_OUTPUT=$(cat /tmp/docker_test_output.log)
        
        echo ""
        if [ $DOCKER_EXIT_CODE -eq 0 ]; then
            echo -e "${GREEN}✅ Docker Bun test completed successfully${NC}"
        else
            echo -e "${RED}❌ Docker Bun test failed with exit code $DOCKER_EXIT_CODE${NC}"
        fi
        
        echo ""
        echo -e "${BLUE}📊 Docker Bun Test Metrics:${NC}"
        extract_metrics "$DOCKER_OUTPUT" "Docker Bun"
        
        rm -f /tmp/docker_test_output.log
    else
        echo -e "${RED}❌ test-docker-bun.sh not found${NC}"
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
        
        rm -f /tmp/node_bun_test_output.log
    else
        echo -e "${RED}❌ test-docker-node-bun.sh not found${NC}"
        NODE_BUN_EXIT_CODE=1
    fi
    
    echo "================================================"
    echo ""
fi

# Run Ubuntu + Bun Docker Test
if [ "$RUN_UBUNTU_BUN" = true ]; then
    echo -e "${BLUE}🟠 Starting UBUNTU + BUN Docker test...${NC}"
    echo "================================================"
    
    if [ -f "test-docker-ubuntu-bun.sh" ]; then
        chmod +x test-docker-ubuntu-bun.sh
        echo -e "${YELLOW}⏳ Running Ubuntu + Bun Docker test (this will take ~3-5 minutes)...${NC}"
        echo ""
        
        ./test-docker-ubuntu-bun.sh 2>&1 | tee /tmp/ubuntu_bun_test_output.log
        UBUNTU_BUN_EXIT_CODE=${PIPESTATUS[0]}
        UBUNTU_BUN_OUTPUT=$(cat /tmp/ubuntu_bun_test_output.log)
        
        echo ""
        if [ $UBUNTU_BUN_EXIT_CODE -eq 0 ]; then
            echo -e "${GREEN}✅ Ubuntu + Bun Docker test completed successfully${NC}"
        else
            echo -e "${RED}❌ Ubuntu + Bun Docker test failed with exit code $UBUNTU_BUN_EXIT_CODE${NC}"
        fi
        
        echo ""
        echo -e "${BLUE}📊 Ubuntu + Bun Docker Test Metrics:${NC}"
        extract_metrics "$UBUNTU_BUN_OUTPUT" "Ubuntu + Bun Docker"
        
        rm -f /tmp/ubuntu_bun_test_output.log
    else
        echo -e "${RED}❌ test-docker-ubuntu-bun.sh not found${NC}"
        UBUNTU_BUN_EXIT_CODE=1
    fi
    
    echo "================================================"
    echo ""
fi

# Run Debian + Bun Docker Test
if [ "$RUN_DEBIAN_BUN" = true ]; then
    echo -e "${BLUE}🔵 Starting DEBIAN + BUN Docker test...${NC}"
    echo "================================================"
    
    if [ -f "test-docker-debian-bun.sh" ]; then
        chmod +x test-docker-debian-bun.sh
        echo -e "${YELLOW}⏳ Running Debian + Bun Docker test (this will take ~3-5 minutes)...${NC}"
        echo ""
        
        ./test-docker-debian-bun.sh 2>&1 | tee /tmp/debian_bun_test_output.log
        DEBIAN_BUN_EXIT_CODE=${PIPESTATUS[0]}
        DEBIAN_BUN_OUTPUT=$(cat /tmp/debian_bun_test_output.log)
        
        echo ""
        if [ $DEBIAN_BUN_EXIT_CODE -eq 0 ]; then
            echo -e "${GREEN}✅ Debian + Bun Docker test completed successfully${NC}"
        else
            echo -e "${RED}❌ Debian + Bun Docker test failed with exit code $DEBIAN_BUN_EXIT_CODE${NC}"
        fi
        
        echo ""
        echo -e "${BLUE}📊 Debian + Bun Docker Test Metrics:${NC}"
        extract_metrics "$DEBIAN_BUN_OUTPUT" "Debian + Bun Docker"
        
        rm -f /tmp/debian_bun_test_output.log
    else
        echo -e "${RED}❌ test-docker-debian-bun.sh not found${NC}"
        DEBIAN_BUN_EXIT_CODE=1
    fi
    
    echo "================================================"
    echo ""
fi

# Run Alpine + Bun Docker Test
if [ "$RUN_ALPINE_BUN" = true ]; then
    echo -e "${BLUE}⛰️  Starting ALPINE + BUN Docker test...${NC}"
    echo "================================================"
    
    if [ -f "test-docker-alpine-bun.sh" ]; then
        chmod +x test-docker-alpine-bun.sh
        echo -e "${YELLOW}⏳ Running Alpine + Bun Docker test (this will take ~3-5 minutes)...${NC}"
        echo ""
        
        ./test-docker-alpine-bun.sh 2>&1 | tee /tmp/alpine_bun_test_output.log
        ALPINE_BUN_EXIT_CODE=${PIPESTATUS[0]}
        ALPINE_BUN_OUTPUT=$(cat /tmp/alpine_bun_test_output.log)
        
        echo ""
        if [ $ALPINE_BUN_EXIT_CODE -eq 0 ]; then
            echo -e "${GREEN}✅ Alpine + Bun Docker test completed successfully${NC}"
        else
            echo -e "${RED}❌ Alpine + Bun Docker test failed with exit code $ALPINE_BUN_EXIT_CODE${NC}"
        fi
        
        echo ""
        echo -e "${BLUE}📊 Alpine + Bun Docker Test Metrics:${NC}"
        extract_metrics "$ALPINE_BUN_OUTPUT" "Alpine + Bun Docker"
        
        rm -f /tmp/alpine_bun_test_output.log
    else
        echo -e "${RED}❌ test-docker-alpine-bun.sh not found${NC}"
        ALPINE_BUN_EXIT_CODE=1
    fi
    
    echo "================================================"
    echo ""
fi

# Summary
echo -e "${CYAN}📋 COMPREHENSIVE TEST MATRIX SUMMARY${NC}"
echo "===================================="

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

if [ "$RUN_UBUNTU_BUN" = true ]; then
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [ $UBUNTU_BUN_EXIT_CODE -eq 0 ]; then
        SUCCESSFUL_TESTS=$((SUCCESSFUL_TESTS + 1))
    fi
fi

if [ "$RUN_DEBIAN_BUN" = true ]; then
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [ $DEBIAN_BUN_EXIT_CODE -eq 0 ]; then
        SUCCESSFUL_TESTS=$((SUCCESSFUL_TESTS + 1))
    fi
fi

if [ "$RUN_ALPINE_BUN" = true ]; then
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    if [ $ALPINE_BUN_EXIT_CODE -eq 0 ]; then
        SUCCESSFUL_TESTS=$((SUCCESSFUL_TESTS + 1))
    fi
fi

echo -e "${BLUE}📊 Test Results: $SUCCESSFUL_TESTS/$TOTAL_TESTS tests passed${NC}"
echo ""

if [ $SUCCESSFUL_TESTS -eq $TOTAL_TESTS ] && [ $TOTAL_TESTS -gt 0 ]; then
    echo -e "${GREEN}✅ All tests completed successfully${NC}"
    echo ""
    echo -e "${MAGENTA}🔬 CONTAINERIZATION ANALYSIS:${NC}"
    echo ""
    echo "This comprehensive test matrix helps isolate:"
    echo ""
    echo "🎯 RUNTIME vs CONTAINERIZATION:"
    echo "  • Local Bun (clean) vs Any Container + Bun (leaks) = Container triggers leak"
    echo "  • Node.js (clean) vs Bun-in-Node (leaks) = Bun runtime issue"
    echo ""
    echo "🐧 LINUX DISTRIBUTION EFFECTS:"
    echo "  • Compare Ubuntu vs Debian vs Alpine + Bun containers"
    echo "  • If all show leaks = general containerization issue"
    echo "  • If specific distros leak = distribution-specific trigger"
    echo ""
    echo "🔍 CRITICAL FINDINGS:"
    echo "  • If Bun-in-Node leaks = DEFINITIVE Bun runtime bug"
    echo "  • If all containers leak but local is clean = containerization triggers bug"
    echo "  • Pattern consistency across distros = confirms systematic issue"
    echo ""
    echo "📈 LEAK PATTERN ANALYSIS:"
    echo "  • Headers/NodeHTTPResponse objects accumulating ~1.3 per request"
    echo "  • Memory growth in RSS/HeapUsed metrics"
    echo "  • Continued growth during 2-minute wait periods"
    echo ""
else
    echo -e "${YELLOW}⚠️  Partial success: $SUCCESSFUL_TESTS/$TOTAL_TESTS tests passed${NC}"
fi

echo ""
echo -e "${BLUE}📖 Usage Examples:${NC}"
echo "  ./run-comprehensive-tests.sh                    # Run all 7 tests (full matrix)"
echo "  ./run-comprehensive-tests.sh --local-only       # Test only local Bun"
echo "  ./run-comprehensive-tests.sh --ubuntu-bun-only  # Test only Ubuntu + Bun"
echo "  ./run-comprehensive-tests.sh --alpine-bun-only  # Test only Alpine + Bun"
echo ""
echo "🚀 This comprehensive analysis provides definitive evidence for Bun team!" 