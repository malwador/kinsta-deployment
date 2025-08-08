#!/bin/bash

# Check if all required dependencies are available for the Kinsta deployment action

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔍 Checking Dependencies for Kinsta Action${NC}\n"

# Check if running on supported OS
check_os() {
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo -e "${GREEN}✅ Running on Linux${NC}"
        OS="linux"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        echo -e "${GREEN}✅ Running on macOS${NC}"
        OS="macos"
    else
        echo -e "${RED}❌ Unsupported OS: $OSTYPE${NC}"
        echo "This action is designed for Linux (GitHub Actions) and macOS"
        exit 1
    fi
}

# Check for required commands
check_command() {
    local cmd="$1"
    local description="$2"
    local install_hint="$3"
    
    if command -v "$cmd" &> /dev/null; then
        echo -e "${GREEN}✅ $cmd found${NC} - $description"
        return 0
    else
        echo -e "${RED}❌ $cmd not found${NC} - $description"
        if [ -n "$install_hint" ]; then
            echo -e "${YELLOW}   Install with: $install_hint${NC}"
        fi
        return 1
    fi
}

# Main dependency checks
check_dependencies() {
    local missing_deps=0
    
    echo -e "${BLUE}Checking required commands...${NC}"
    
    # Essential commands for the action
    check_command "lftp" "FTP client for file synchronization" "apt-get install lftp (Ubuntu) or brew install lftp (macOS)" || ((missing_deps++))
    check_command "rsync" "File synchronization utility" "apt-get install rsync (Ubuntu) or brew install rsync (macOS)" || ((missing_deps++))
    check_command "ssh" "SSH client for secure connections" "apt-get install openssh-client (Ubuntu)" || ((missing_deps++))
    check_command "curl" "HTTP client for downloading files" "apt-get install curl (Ubuntu) or brew install curl (macOS)" || ((missing_deps++))
    check_command "unzip" "ZIP archive extraction utility" "apt-get install unzip (Ubuntu) or brew install unzip (macOS)" || ((missing_deps++))
    check_command "file" "File type detection utility" "apt-get install file (Ubuntu) or brew install file (macOS)" || ((missing_deps++))
    check_command "find" "File search utility" "Part of coreutils" || ((missing_deps++))
    check_command "stat" "File status utility" "Part of coreutils" || ((missing_deps++))
    check_command "du" "Disk usage utility" "Part of coreutils" || ((missing_deps++))
    check_command "grep" "Text search utility" "Part of coreutils" || ((missing_deps++))
    check_command "wc" "Word/line count utility" "Part of coreutils" || ((missing_deps++))
    
    echo ""
    
    if [ $missing_deps -eq 0 ]; then
        echo -e "${GREEN}🎉 All dependencies are satisfied!${NC}"
        return 0
    else
        echo -e "${RED}❌ $missing_deps dependencies are missing${NC}"
        return 1
    fi
}

# Check file permissions
check_file_permissions() {
    echo -e "${BLUE}Checking file permissions...${NC}"
    
    local script_dir="$(dirname "$0")"
    local deploy_script="$script_dir/deploy.sh"
    local test_script="$script_dir/test-local.sh"
    
    if [ -x "$deploy_script" ]; then
        echo -e "${GREEN}✅ deploy.sh is executable${NC}"
    else
        echo -e "${RED}❌ deploy.sh is not executable${NC}"
        echo -e "${YELLOW}   Fix with: chmod +x $deploy_script${NC}"
    fi
    
    if [ -x "$test_script" ]; then
        echo -e "${GREEN}✅ test-local.sh is executable${NC}"
    else
        echo -e "${RED}❌ test-local.sh is not executable${NC}"
        echo -e "${YELLOW}   Fix with: chmod +x $test_script${NC}"
    fi
}

# Check action file structure
check_action_structure() {
    echo -e "${BLUE}Checking action file structure...${NC}"
    
    local action_root="$(dirname "$0")/.."
    local required_files=(
        "action.yml"
        "scripts/deploy.sh"
        "README.md"
    )
    
    for file in "${required_files[@]}"; do
        if [ -f "$action_root/$file" ]; then
            echo -e "${GREEN}✅ $file exists${NC}"
        else
            echo -e "${RED}❌ $file missing${NC}"
        fi
    done
}

# Test lftp functionality
test_lftp() {
    echo -e "${BLUE}Testing lftp functionality...${NC}"
    
    if command -v lftp &> /dev/null; then
        # Test basic lftp syntax
        if lftp -c "help" &> /dev/null; then
            echo -e "${GREEN}✅ lftp is working correctly${NC}"
        else
            echo -e "${YELLOW}⚠️  lftp may have issues${NC}"
        fi
    else
        echo -e "${RED}❌ lftp not available for testing${NC}"
    fi
}

# Main execution
main() {
    check_os
    echo ""
    
    check_dependencies
    local deps_ok=$?
    echo ""
    
    check_file_permissions
    echo ""
    
    check_action_structure
    echo ""
    
    test_lftp
    echo ""
    
    if [ $deps_ok -eq 0 ]; then
        echo -e "${GREEN}🚀 System is ready for Kinsta deployment!${NC}"
        echo ""
        echo -e "${BLUE}Next steps:${NC}"
        echo "1. Copy env.example to .env.local and configure your Kinsta credentials"
        echo "2. Run ./scripts/test-local.sh to test the deployment"
        echo "3. Use the action in your GitHub workflow"
        exit 0
    else
        echo -e "${RED}❌ Please install missing dependencies before using this action${NC}"
        exit 1
    fi
}

main
