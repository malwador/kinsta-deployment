#!/bin/bash

# Local testing script for the Kinsta deployment action
# This allows you to test the deployment script locally before using it in GitHub Actions

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}🧪 Kinsta Action Local Test${NC}\n"

# Check if .env.local exists for local testing
if [ -f ".env.local" ]; then
    echo -e "${GREEN}Loading environment variables from .env.local...${NC}"
    set -a
    source .env.local
    set +a
else
    echo -e "${YELLOW}⚠️  .env.local not found. Create one with your test credentials:${NC}"
    echo ""
    echo "KINSTA_HOST_IP=123.456.789.012"
    echo "KINSTA_USERNAME=your-username"
    echo "KINSTA_PASSWORD=your-password"
    echo "KINSTA_PORT=12345"
    echo "SOURCE_PATH=."
    echo "TARGET_PATH=/www/your-site_123/public"
    echo "EXCLUDE_PATTERNS=.git,.github,node_modules,.env,.DS_Store,*.log"
    echo "DRY_RUN=true"
    echo "VERBOSE=true"
    echo "INSTALL_KINSTA_MU_PLUGIN=true"
    echo "KINSTA_MU_PLUGIN_PATH=wp-content/mu-plugins"
    echo "PURGE_KINSTA_CACHE=true"
    echo ""
    echo -e "${RED}Exiting...${NC}"
    exit 1
fi

# Validate that required variables are set
required_vars=("KINSTA_HOST_IP" "KINSTA_USERNAME" "KINSTA_PASSWORD" "KINSTA_PORT" "TARGET_PATH")
missing_vars=()

for var in "${required_vars[@]}"; do
    if [ -z "${!var}" ]; then
        missing_vars+=("$var")
    fi
done

if [ ${#missing_vars[@]} -ne 0 ]; then
    echo -e "${RED}❌ Missing required environment variables: ${missing_vars[*]}${NC}"
    exit 1
fi

echo -e "${GREEN}✅ All required environment variables are set${NC}"
echo ""
echo -e "${BLUE}Configuration:${NC}"
echo "Host IP: $KINSTA_HOST_IP"
echo "Username: $KINSTA_USERNAME"
echo "Port: $KINSTA_PORT"
echo "Source: ${SOURCE_PATH:-.}"
echo "Target: $TARGET_PATH"
echo "Dry Run: ${DRY_RUN:-true}"
echo "Verbose: ${VERBOSE:-false}"
echo "Install MU Plugin: ${INSTALL_KINSTA_MU_PLUGIN:-true}"
echo "MU Plugin Path: ${KINSTA_MU_PLUGIN_PATH:-wp-content/mu-plugins}"
echo "Purge Cache: ${PURGE_KINSTA_CACHE:-true}"
echo ""

# Ask for confirmation
read -p "Do you want to proceed with the deployment test? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo -e "${YELLOW}Test cancelled.${NC}"
    exit 0
fi

echo -e "${BLUE}🚀 Starting deployment test...${NC}"
echo ""

# Export environment variables for the script
export KINSTA_HOST_IP KINSTA_USERNAME KINSTA_PASSWORD KINSTA_PORT TARGET_PATH
export SOURCE_PATH="${SOURCE_PATH:-.}"
export EXCLUDE_PATTERNS="${EXCLUDE_PATTERNS:-.git,.github,node_modules,.env,.DS_Store,*.log}"
export DRY_RUN="${DRY_RUN:-true}"
export VERBOSE="${VERBOSE:-false}"
export INSTALL_KINSTA_MU_PLUGIN="${INSTALL_KINSTA_MU_PLUGIN:-true}"
export KINSTA_MU_PLUGIN_PATH="${KINSTA_MU_PLUGIN_PATH:-wp-content/mu-plugins}"
export PURGE_KINSTA_CACHE="${PURGE_KINSTA_CACHE:-true}"

# Run the deployment script
./scripts/deploy.sh

echo ""
echo -e "${GREEN}✅ Test completed!${NC}"

# Show deployment statistics if available
if [ -f /tmp/deployment_stats.txt ]; then
    echo ""
    echo -e "${BLUE}📊 Deployment Statistics:${NC}"
    cat /tmp/deployment_stats.txt
fi
