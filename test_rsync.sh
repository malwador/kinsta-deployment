#!/bin/bash

# Quick test script to verify rsync command construction

# Set test variables
KINSTA_HOST_IP="123.456.789.012"
KINSTA_USERNAME="test_user"
KINSTA_PORT="12345"
SOURCE_PATH="/tmp/test_source"
TARGET_PATH="/www/test_123/public"
EXCLUDE_PATTERNS=".git,.github,node_modules,.env,.DS_Store,*.log"
VERBOSE="true"
DRY_RUN="true"

# Define the function locally
build_rsync_command() {
    local rsync_opts=()
    
    # Base rsync options
    rsync_opts+=("-avz")  # archive, verbose, compress
    rsync_opts+=("--update")  # only transfer newer files
    rsync_opts+=("--timeout=300")  # 5 minute timeout
    
    # SSH options for Kinsta
    rsync_opts+=("-e")
    rsync_opts+=("ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $KINSTA_PORT")
    
    # Verbose mode
    if [ "$VERBOSE" = "true" ]; then
        rsync_opts+=("--progress")
        rsync_opts+=("--stats")
    else
        rsync_opts+=("--quiet")
    fi
    
    # Dry run mode
    if [ "$DRY_RUN" = "true" ]; then
        rsync_opts+=("--dry-run")
    fi
    
    # Add exclude patterns
    IFS=',' read -ra PATTERNS <<< "$EXCLUDE_PATTERNS"
    for pattern in "${PATTERNS[@]}"; do
        pattern=$(echo "$pattern" | xargs) # trim whitespace
        if [ -n "$pattern" ]; then
            rsync_opts+=("--exclude=$pattern")
        fi
    done
    
    # Source and destination
    rsync_opts+=("$SOURCE_PATH/")
    rsync_opts+=("$KINSTA_USERNAME@$KINSTA_HOST_IP:$TARGET_PATH")
    
    printf '%q ' "${rsync_opts[@]}"
}

# Test the rsync command construction
echo "Testing rsync command construction:"
echo "=================================="

rsync_test_cmd=$(build_rsync_command)

echo "Generated command:"
echo "$rsync_test_cmd"

echo ""
echo "Full command:"
echo "rsync $rsync_test_cmd"
