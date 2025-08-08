#!/bin/bash

# Deploy WordPress to Kinsta via sFTP with efficient file synchronization
# This script only transfers files that are newer or different in size

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log messages
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

# Validate required environment variables
validate_inputs() {
    local missing_vars=()
    
    if [ -z "$KINSTA_HOST_IP" ]; then missing_vars+=("KINSTA_HOST_IP"); fi
    if [ -z "$KINSTA_USERNAME" ]; then missing_vars+=("KINSTA_USERNAME"); fi
    if [ -z "$KINSTA_PASSWORD" ]; then missing_vars+=("KINSTA_PASSWORD"); fi
    if [ -z "$KINSTA_PORT" ]; then missing_vars+=("KINSTA_PORT"); fi
    if [ -z "$TARGET_PATH" ]; then missing_vars+=("TARGET_PATH"); fi
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        exit 1
    fi
}

# Set default values for optional variables
SOURCE_PATH=${SOURCE_PATH:-.}
EXCLUDE_PATTERNS=${EXCLUDE_PATTERNS:-.git,.github,node_modules,.env,.DS_Store,*.log}
DRY_RUN=${DRY_RUN:-false}
VERBOSE=${VERBOSE:-false}
INSTALL_KINSTA_MU_PLUGIN=${INSTALL_KINSTA_MU_PLUGIN:-true}
KINSTA_MU_PLUGIN_PATH=${KINSTA_MU_PLUGIN_PATH:-wp-content/mu-plugins}
PURGE_KINSTA_CACHE=${PURGE_KINSTA_CACHE:-true}

# Statistics tracking
START_TIME=$(date +%s)
FILES_TRANSFERRED=0
BYTES_TRANSFERRED=0

# Build rsync command for efficient synchronization
build_rsync_command() {
    local rsync_opts=()
    
    # Base rsync options
    rsync_opts+=("-avz")  # archive, verbose, compress
    rsync_opts+=("--update")  # only transfer newer files
    rsync_opts+=("--delete")  # delete files that don't exist in source
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
    local exclude_opts
    exclude_opts=$(build_rsync_exclude_options)
    if [ -n "$exclude_opts" ]; then
        rsync_opts+=($exclude_opts)
    fi
    
    # Source and destination
    rsync_opts+=("$SOURCE_PATH/")
    rsync_opts+=("$KINSTA_USERNAME@$KINSTA_HOST_IP:$TARGET_PATH")
    
    echo "${rsync_opts[@]}"
}

# Build exclude options for rsync
build_rsync_exclude_options() {
    local exclude_opts=()
    IFS=',' read -ra PATTERNS <<< "$EXCLUDE_PATTERNS"
    
    for pattern in "${PATTERNS[@]}"; do
        pattern=$(echo "$pattern" | xargs) # trim whitespace
        if [ -n "$pattern" ]; then
            exclude_opts+=("--exclude=$pattern")
        fi
    done
    
    echo "${exclude_opts[@]}"
}

# Test SSH connection to Kinsta server
test_ssh_connection() {
    log "Testing SSH connection to Kinsta server..."
    
    local ssh_test_cmd="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p $KINSTA_PORT $KINSTA_USERNAME@$KINSTA_HOST_IP 'echo \"SSH connection successful\"'"
    
    if eval "$ssh_test_cmd" 2>/dev/null; then
        log_success "SSH connection test successful"
        return 0
    else
        log_error "SSH connection test failed"
        return 1
    fi
}

# Generate deployment statistics
generate_stats() {
    local end_time=$(date +%s)
    local deployment_time=$((end_time - START_TIME))
    
    cat > /tmp/deployment_stats.txt << EOF
FILES_TRANSFERRED:$FILES_TRANSFERRED
BYTES_TRANSFERRED:$BYTES_TRANSFERRED
DEPLOYMENT_TIME:$deployment_time
EOF
}

# Main deployment function
deploy() {
    log "Starting WordPress deployment to Kinsta..."
    log "Host IP: $KINSTA_HOST_IP"
    log "Port: $KINSTA_PORT"
    log "Source: $SOURCE_PATH"
    log "Target: $TARGET_PATH"
    log "Dry Run: $DRY_RUN"
    
    validate_inputs
    
    # Check if source directory exists
    if [ ! -d "$SOURCE_PATH" ]; then
        log_error "Source directory '$SOURCE_PATH' does not exist"
        exit 1
    fi
    
    # Test SSH connection
    if ! test_ssh_connection; then
        log_error "Failed to connect to Kinsta SSH server"
        exit 1
    fi
    
    # Count files in source directory for statistics
    local total_files
    total_files=$(find "$SOURCE_PATH" -type f | wc -l 2>/dev/null || echo "0")
    log "Found $total_files files in source directory"
    
    # Build rsync command
    local rsync_cmd
    read -ra rsync_cmd <<< "$(build_rsync_command)"
    
    log "Starting file synchronization with rsync..."
    if [ "$VERBOSE" = "true" ]; then
        log "Executing rsync with verbose output..."
        log "Command: rsync ${rsync_cmd[*]}"
    fi
    
    # Create temporary output file for rsync statistics
    local rsync_output="/tmp/rsync_output.log"
    
    # Execute rsync with progress monitoring
    if rsync "${rsync_cmd[@]}" 2>&1 | tee "$rsync_output"; then
        log_success "File synchronization completed successfully"
        
        # Parse rsync output for statistics
        if [ -f "$rsync_output" ]; then
            # Extract statistics from rsync output
            if grep -q "Number of files transferred" "$rsync_output"; then
                FILES_TRANSFERRED=$(grep "Number of files transferred" "$rsync_output" | awk '{print $5}' | tr -d ',')
            elif grep -q "sent.*bytes.*received.*bytes" "$rsync_output"; then
                # Alternative parsing for different rsync output formats
                FILES_TRANSFERRED=$(grep -c "^>" "$rsync_output" 2>/dev/null || echo "0")
            else
                FILES_TRANSFERRED="0"
            fi
            
            # Extract bytes transferred
            if grep -q "Total bytes sent" "$rsync_output"; then
                BYTES_TRANSFERRED=$(grep "Total bytes sent" "$rsync_output" | awk '{print $4}' | tr -d ',')
            elif grep -q "sent.*bytes" "$rsync_output"; then
                BYTES_TRANSFERRED=$(grep "sent.*bytes" "$rsync_output" | sed 's/.*sent \([0-9,]*\) bytes.*/\1/' | tr -d ',')
            else
                # Fallback to source directory size
                BYTES_TRANSFERRED=$(du -sb "$SOURCE_PATH" 2>/dev/null | cut -f1 || echo "0")
            fi
            
            log "Files transferred: $FILES_TRANSFERRED"
            log "Bytes transferred: $BYTES_TRANSFERRED"
        fi
    else
        log_error "File synchronization failed"
        exit 1
    fi
    
    # Clean up temporary files
    rm -f "$rsync_output"
    
    # Install Kinsta MU Plugin if enabled
    if [ "$INSTALL_KINSTA_MU_PLUGIN" = "true" ]; then
        log "Installing Kinsta MU Plugin..."
        local script_dir="$(dirname "$0")"
        if [ -f "$script_dir/install-mu-plugin.sh" ]; then
            # Export environment variables for the MU plugin script
            export TARGET_PATH KINSTA_MU_PLUGIN_PATH DRY_RUN VERBOSE
            export KINSTA_HOST_IP KINSTA_USERNAME KINSTA_PASSWORD KINSTA_PORT
            export INSTALL_KINSTA_MU_PLUGIN
            
            if "$script_dir/install-mu-plugin.sh"; then
                log_success "Kinsta MU Plugin installation completed"
                
                # Purge cache after successful MU Plugin installation
                if [ "$PURGE_KINSTA_CACHE" = "true" ]; then
                    log "Purging Kinsta cache after MU Plugin installation..."
                    if [ -f "$script_dir/purge-cache.sh" ]; then
                        # Export environment variables for cache purge script
                        export PURGE_KINSTA_CACHE
                        
                        if "$script_dir/purge-cache.sh"; then
                            log_success "Kinsta cache purged successfully"
                        else
                            log_warning "Cache purge failed, but deployment will continue"
                            # Don't exit on cache purge failure
                        fi
                    else
                        log_warning "Cache purge script not found: $script_dir/purge-cache.sh"
                    fi
                else
                    log "Kinsta cache purge skipped (disabled)"
                fi
            else
                log_error "Kinsta MU Plugin installation failed"
                # Don't exit on MU plugin failure, just warn
            fi
        else
            log_warning "MU Plugin installation script not found: $script_dir/install-mu-plugin.sh"
        fi
    else
        log "Kinsta MU Plugin installation skipped (disabled)"
        
        # Purge cache even if MU Plugin installation is disabled
        if [ "$PURGE_KINSTA_CACHE" = "true" ]; then
            log "Purging Kinsta cache after deployment..."
            local script_dir="$(dirname "$0")"
            if [ -f "$script_dir/purge-cache.sh" ]; then
                # Export environment variables for cache purge script
                export TARGET_PATH DRY_RUN VERBOSE PURGE_KINSTA_CACHE
                export KINSTA_HOST_IP KINSTA_USERNAME KINSTA_PASSWORD KINSTA_PORT
                
                if "$script_dir/purge-cache.sh"; then
                    log_success "Kinsta cache purged successfully"
                else
                    log_warning "Cache purge failed, but deployment completed"
                fi
            else
                log_warning "Cache purge script not found: $script_dir/purge-cache.sh"
            fi
        fi
    fi
    
    # Generate final statistics
    generate_stats
    
    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    
    log_success "Deployment completed in ${duration} seconds"
    log_success "Files transferred: $FILES_TRANSFERRED"
    log_success "Estimated bytes transferred: $BYTES_TRANSFERRED"
    
    if [ "$DRY_RUN" = "true" ]; then
        log_warning "This was a dry run - no files were actually transferred"
    fi
}

# Trap for cleanup
cleanup() {
    rm -f /tmp/lftp_script.txt /tmp/file_list.txt /tmp/lftp_output.log
}
trap cleanup EXIT

# Run deployment
deploy
