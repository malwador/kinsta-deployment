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

# Create lftp script for efficient synchronization
create_lftp_script() {
    local script_file="./tmp/lftp_script.txt"
    
    cat > "$script_file" << EOF
set sftp:auto-confirm yes
set sftp:connect-program "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
set net:timeout 30
set net:max-retries 3
set net:reconnect-interval-base 5

# Connect to Kinsta
open sftp://$KINSTA_USERNAME:$KINSTA_PASSWORD@$KINSTA_HOST_IP:$KINSTA_PORT

# Set verbose mode if requested
$([ "$VERBOSE" = "true" ] && echo "set cmd:verbose yes")

# Change to target directory
cd $TARGET_PATH

# Local directory
lcd $SOURCE_PATH

# Mirror with options for efficiency
mirror \\
    --verbose=$([ "$VERBOSE" = "true" ] && echo "3" || echo "1") \\
    --only-newer \\
    --no-empty-dirs \\
    --parallel=3 \\
    $([ "$DRY_RUN" = "true" ] && echo "--dry-run") \\
    $(build_exclude_options) \\
    . .

quit
EOF

    echo "$script_file"
}

# Build exclude options for lftp
build_exclude_options() {
    local exclude_opts=""
    IFS=',' read -ra PATTERNS <<< "$EXCLUDE_PATTERNS"
    
    for pattern in "${PATTERNS[@]}"; do
        pattern=$(echo "$pattern" | xargs) # trim whitespace
        if [ -n "$pattern" ]; then
            exclude_opts="$exclude_opts --exclude-glob=$pattern"
        fi
    done
    
    echo "$exclude_opts"
}

# Create rsync-based alternative for comparison/backup
create_file_list() {
    local list_file="/tmp/file_list.txt"
    
    log "Creating file list for transfer analysis..."
    
    # Build exclude options for find
    local find_excludes=""
    IFS=',' read -ra PATTERNS <<< "$EXCLUDE_PATTERNS"
    
    for pattern in "${PATTERNS[@]}"; do
        pattern=$(echo "$pattern" | xargs)
        if [ -n "$pattern" ]; then
            # Convert glob pattern to find expression
            case "$pattern" in
                .*)
                    find_excludes="$find_excludes -name '$pattern' -prune -o"
                    ;;
                *.*)
                    find_excludes="$find_excludes -name '$pattern' -prune -o"
                    ;;
                *)
                    find_excludes="$find_excludes -name '$pattern' -prune -o"
                    ;;
            esac
        fi
    done
    
    # Create file list with sizes and timestamps
    cd "$SOURCE_PATH"
    eval "find . $find_excludes -type f -print" | while read -r file; do
        if [ -f "$file" ]; then
            size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
            mtime=$(stat -f%m "$file" 2>/dev/null || stat -c%Y "$file" 2>/dev/null || echo "0")
            echo "$file|$size|$mtime"
        fi
    done > "$list_file"
    
    echo "$list_file"
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
    
    # Test sFTP connection
    log "Testing sFTP connection..."
    if ! lftp -c "open sftp://$KINSTA_USERNAME:$KINSTA_PASSWORD@$KINSTA_HOST_IP:$KINSTA_PORT; quit" 2>/dev/null; then
        log_error "Failed to connect to Kinsta sFTP server"
        exit 1
    fi
    log_success "sFTP connection successful"
    
    # Create file list for analysis
    local file_list
    file_list=$(create_file_list)
    local total_files
    total_files=$(wc -l < "$file_list")
    
    log "Found $total_files files to analyze for transfer"
    
    # Create and execute lftp script
    local lftp_script
    lftp_script=$(create_lftp_script)
    
    log "Starting file synchronization..."
    if [ "$VERBOSE" = "true" ]; then
        log "Executing lftp script with verbose output..."
    fi
    
    # Execute lftp with progress monitoring
    if lftp -f "$lftp_script" 2>&1 | tee /tmp/lftp_output.log; then
        log_success "File synchronization completed successfully"
        
        # Parse lftp output for statistics (basic parsing)
        if [ -f /tmp/lftp_output.log ]; then
            FILES_TRANSFERRED=$(grep -c "Transferring\|STOR\|get\|put" /tmp/lftp_output.log 2>/dev/null || echo "0")
            # Estimate bytes transferred (this is approximate)
            BYTES_TRANSFERRED=$(du -sb "$SOURCE_PATH" 2>/dev/null | cut -f1 || echo "0")
        fi
    else
        log_error "File synchronization failed"
        exit 1
    fi
    
    # Clean up temporary files
    rm -f "$lftp_script" "$file_list" /tmp/lftp_output.log
    
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
