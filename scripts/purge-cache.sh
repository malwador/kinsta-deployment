#!/bin/bash

# Purge Kinsta Cache using WP-CLI
# Executes wp kinsta cache purge --all command on the remote server

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log messages
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] [Cache-Purge]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] [Cache-Purge]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] [Cache-Purge]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] [Cache-Purge]${NC} $1"
}

# Purge Kinsta cache using WP-CLI
purge_kinsta_cache() {
    local target_path="$1"
    local dry_run="$2"
    local verbose="$3"
    
    log "Starting Kinsta cache purge..."
    
    # Validate inputs
    if [ -z "$target_path" ]; then
        log_error "Target path is required"
        return 1
    fi
    
    log "Target path: $target_path"
    
    if [ "$dry_run" = "true" ]; then
        log_warning "DRY RUN: Would execute 'wp kinsta cache purge --all' in: $target_path"
        return 0
    fi
    
    # Test SSH connection first
    log "Testing SSH connection..."
    if ! test_ssh_connection; then
        log_error "SSH connection test failed"
        return 1
    fi
    
    log_success "SSH connection successful"
    
    # Execute WP-CLI cache purge command
    execute_wp_cli_cache_purge "$target_path" "$verbose"
}

# Test SSH connection to Kinsta
test_ssh_connection() {
    local ssh_test_cmd="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p $KINSTA_PORT $KINSTA_USERNAME@$KINSTA_HOST_IP 'echo \"SSH connection successful\"'"
    
    if eval "$ssh_test_cmd" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Execute WP-CLI cache purge via SSH
execute_wp_cli_cache_purge() {
    local target_path="$1"
    local verbose="$2"
    
    log "Executing WP-CLI cache purge command..."
    
    # Construct SSH command to run WP-CLI
    local ssh_command="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30 -p $KINSTA_PORT $KINSTA_USERNAME@$KINSTA_HOST_IP"
    
    # WP-CLI command to execute
    local wp_cli_command="cd '$target_path' && wp kinsta cache purge --all"
    
    if [ "$verbose" = "true" ]; then
        log "Executing SSH command: $ssh_command '$wp_cli_command'"
    fi
    
    # Execute the command and capture output
    local temp_output="/tmp/wp_cli_cache_output.log"
    
    if $ssh_command "$wp_cli_command" > "$temp_output" 2>&1; then
        log_success "Cache purge command executed successfully"
        
        # Show output if verbose
        if [ "$verbose" = "true" ] && [ -f "$temp_output" ]; then
            log "WP-CLI output:"
            while IFS= read -r line; do
                echo "  $line"
            done < "$temp_output"
        fi
        
        # Check for success indicators in output
        if grep -q "success\|purged\|cleared\|flushed" "$temp_output" 2>/dev/null; then
            log_success "Kinsta cache purged successfully"
        else
            log_warning "Cache purge completed, but success confirmation not found in output"
        fi
        
        rm -f "$temp_output"
        return 0
    else
        log_error "Failed to execute cache purge command"
        
        # Show error output
        if [ -f "$temp_output" ]; then
            log "Error output:"
            while IFS= read -r line; do
                echo "  $line"
            done < "$temp_output"
        fi
        
        rm -f "$temp_output"
        return 1
    fi
}

# Alternative cache purge using sFTP to execute commands
purge_cache_via_sftp() {
    local target_path="$1"
    local verbose="$2"
    
    log "Attempting cache purge via sFTP with command execution..."
    
    # Create a temporary script file for WP-CLI
    local temp_script="/tmp/wp_cache_purge.sh"
    
    cat > "$temp_script" << EOF
#!/bin/bash
cd '$target_path'
wp kinsta cache purge --all
EOF
    
    chmod +x "$temp_script"
    
    # Create lftp script to upload and execute
    local lftp_script="/tmp/lftp_cache_script.txt"
    
    cat > "$lftp_script" << EOF
set sftp:auto-confirm yes
set sftp:connect-program "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
set net:timeout 30
set net:max-retries 3

# Connect to Kinsta
open sftp://$KINSTA_USERNAME:$KINSTA_PASSWORD@$KINSTA_HOST_IP:$KINSTA_PORT

# Upload the script
put "$temp_script" "$target_path/wp_cache_purge.sh"

# Note: sFTP cannot execute commands directly
# The script is uploaded for manual execution if needed

quit
EOF

    if lftp -f "$lftp_script" 2>/dev/null; then
        log_warning "Cache purge script uploaded to server, but automatic execution via sFTP is not supported"
        log "Manual execution required: ssh to server and run: bash $target_path/wp_cache_purge.sh"
    else
        log_error "Failed to upload cache purge script via sFTP"
    fi
    
    rm -f "$temp_script" "$lftp_script"
}

# Validate WP-CLI availability on remote server
validate_wp_cli() {
    local target_path="$1"
    
    log "Validating WP-CLI availability on remote server..."
    
    local ssh_command="ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p $KINSTA_PORT $KINSTA_USERNAME@$KINSTA_HOST_IP"
    local wp_cli_check="cd '$target_path' && wp --version"
    
    if $ssh_command "$wp_cli_check" 2>/dev/null | grep -q "WP-CLI"; then
        log_success "WP-CLI is available on the remote server"
        return 0
    else
        log_warning "WP-CLI may not be available or accessible on the remote server"
        return 1
    fi
}

# Main execution function
main() {
    local target_path="${TARGET_PATH}"
    local dry_run="${DRY_RUN:-false}"
    local verbose="${VERBOSE:-false}"
    local purge_cache="${PURGE_KINSTA_CACHE:-true}"
    
    # Check if cache purge is enabled
    if [ "$purge_cache" != "true" ]; then
        log "Kinsta cache purge is disabled"
        return 0
    fi
    
    # Validate required environment variables for SSH
    if [ "$dry_run" != "true" ]; then
        local missing_vars=()
        
        if [ -z "$KINSTA_HOST_IP" ]; then missing_vars+=("KINSTA_HOST_IP"); fi
        if [ -z "$KINSTA_USERNAME" ]; then missing_vars+=("KINSTA_USERNAME"); fi
        if [ -z "$KINSTA_PASSWORD" ]; then missing_vars+=("KINSTA_PASSWORD"); fi
        if [ -z "$KINSTA_PORT" ]; then missing_vars+=("KINSTA_PORT"); fi
        if [ -z "$TARGET_PATH" ]; then missing_vars+=("TARGET_PATH"); fi
        
        if [ ${#missing_vars[@]} -ne 0 ]; then
            log_error "Missing required environment variables: ${missing_vars[*]}"
            return 1
        fi
    fi
    
    # Purge the cache
    if purge_kinsta_cache "$target_path" "$dry_run" "$verbose"; then
        log_success "Kinsta cache purge completed successfully"
    else
        log_error "Kinsta cache purge failed"
        
        # Try alternative method as fallback
        log "Attempting alternative cache purge method..."
        if [ "$dry_run" != "true" ]; then
            purge_cache_via_sftp "$target_path" "$verbose"
        fi
        
        return 1
    fi
}

# Run if script is executed directly
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
