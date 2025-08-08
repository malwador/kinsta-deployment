#!/bin/bash

# Install Kinsta MU Plugin
# Downloads and installs the official Kinsta MU Plugin to the specified directory

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to log messages
log() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] [MU-Plugin]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] [MU-Plugin]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] [MU-Plugin]${NC} $1"
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] [MU-Plugin]${NC} $1"
}

# Kinsta MU Plugin download URL
KINSTA_MU_PLUGIN_URL="https://kinsta.com/kinsta-tools/kinsta-mu-plugins.zip"

# Install Kinsta MU Plugin
install_kinsta_mu_plugin() {
    local target_path="$1"
    local mu_plugin_path="$2"
    local dry_run="$3"
    local verbose="$4"
    
    log "Installing Kinsta MU Plugin..."
    
    # Validate inputs
    if [ -z "$target_path" ]; then
        log_error "Target path is required"
        return 1
    fi
    
    if [ -z "$mu_plugin_path" ]; then
        mu_plugin_path="wp-content/mu-plugins"
        log_warning "MU Plugin path not specified, using default: $mu_plugin_path"
    fi
    
    # Construct full MU plugin directory path
    local full_mu_plugin_path="$target_path/$mu_plugin_path"
    
    log "Target path: $target_path"
    log "MU Plugin path: $mu_plugin_path"
    log "Full MU Plugin path: $full_mu_plugin_path"
    
    if [ "$dry_run" = "true" ]; then
        log_warning "DRY RUN: Would install Kinsta MU Plugin to: $full_mu_plugin_path"
        return 0
    fi
    
    # Create temporary directory for download
    local temp_dir="/tmp/kinsta-mu-plugin-$$"
    mkdir -p "$temp_dir"
    
    # Ensure cleanup happens
    trap "rm -rf '$temp_dir'" EXIT
    
    log "Downloading Kinsta MU Plugin from: $KINSTA_MU_PLUGIN_URL"
    
    # Download the MU plugin zip file
    if ! curl -L -o "$temp_dir/kinsta-mu-plugins.zip" "$KINSTA_MU_PLUGIN_URL"; then
        log_error "Failed to download Kinsta MU Plugin"
        return 1
    fi
    
    log_success "Kinsta MU Plugin downloaded successfully"
    
    # Verify the download
    if [ ! -f "$temp_dir/kinsta-mu-plugins.zip" ]; then
        log_error "Downloaded file not found"
        return 1
    fi
    
    # Check if it's a valid zip file
    if ! file "$temp_dir/kinsta-mu-plugins.zip" | grep -q "Zip archive"; then
        log_error "Downloaded file is not a valid ZIP archive"
        return 1
    fi
    
    local zip_size
    zip_size=$(stat -f%z "$temp_dir/kinsta-mu-plugins.zip" 2>/dev/null || stat -c%s "$temp_dir/kinsta-mu-plugins.zip" 2>/dev/null || echo "0")
    log "Downloaded ZIP file size: ${zip_size} bytes"
    
    # Extract the zip file to temp directory
    log "Extracting Kinsta MU Plugin..."
    if ! unzip -q "$temp_dir/kinsta-mu-plugins.zip" -d "$temp_dir/"; then
        log_error "Failed to extract Kinsta MU Plugin"
        return 1
    fi
    
    log_success "Kinsta MU Plugin extracted successfully"
    
    # List extracted contents for debugging
    if [ "$verbose" = "true" ]; then
        log "Extracted contents:"
        find "$temp_dir" -type f -name "*.php" | head -10
    fi
    
    # Install via sFTP
    install_mu_plugin_via_sftp "$temp_dir" "$full_mu_plugin_path" "$verbose"
}

# Install MU Plugin files via sFTP
install_mu_plugin_via_sftp() {
    local temp_dir="$1"
    local remote_mu_plugin_path="$2"
    local verbose="$3"
    
    log "Installing MU Plugin files via sFTP..."
    
    # Create lftp script for MU plugin installation
    local lftp_script="/tmp/lftp_mu_plugin_script.txt"
    
    cat > "$lftp_script" << EOF
set sftp:auto-confirm yes
set sftp:connect-program "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
set net:timeout 30
set net:max-retries 3
set net:reconnect-interval-base 5

# Connect to Kinsta
open sftp://$KINSTA_USERNAME:$KINSTA_PASSWORD@$KINSTA_HOST_IP:$KINSTA_PORT

# Set verbose mode if requested
$([ "$verbose" = "true" ] && echo "set cmd:verbose yes")

# Create the mu-plugins directory if it doesn't exist
mkdir -pf $remote_mu_plugin_path

# Change to the mu-plugins directory
cd $remote_mu_plugin_path

# Upload the MU plugin files
$(find "$temp_dir" -name "*.php" -type f | while read -r file; do
    local_file="$file"
    filename=$(basename "$file")
    echo "put \"$local_file\" \"$filename\""
done)

# Also upload any subdirectories (like kinsta-mu-plugins folder)
$(if [ -d "$temp_dir/kinsta-mu-plugins" ]; then
    echo "mirror --reverse --verbose=$([ "$verbose" = "true" ] && echo "3" || echo "1") \"$temp_dir/kinsta-mu-plugins\" kinsta-mu-plugins"
fi)

quit
EOF

    # Execute lftp script
    if [ "$verbose" = "true" ]; then
        log "Executing sFTP upload with verbose output..."
    fi
    
    if lftp -f "$lftp_script" 2>&1 | tee /tmp/lftp_mu_plugin_output.log; then
        log_success "Kinsta MU Plugin installed successfully via sFTP"
        
        # Count uploaded files
        local uploaded_files
        uploaded_files=$(grep -c "Transferring\|STOR\|put" /tmp/lftp_mu_plugin_output.log 2>/dev/null || echo "0")
        log_success "Uploaded $uploaded_files MU Plugin files"
    else
        log_error "Failed to install MU Plugin via sFTP"
        return 1
    fi
    
    # Clean up temporary lftp script
    rm -f "$lftp_script" /tmp/lftp_mu_plugin_output.log
}

# Validate Kinsta MU Plugin installation
validate_mu_plugin_installation() {
    local remote_mu_plugin_path="$1"
    local verbose="$2"
    
    log "Validating MU Plugin installation..."
    
    # Create lftp script to check if files exist
    local lftp_check_script="/tmp/lftp_check_mu_plugin.txt"
    
    cat > "$lftp_check_script" << EOF
set sftp:auto-confirm yes
set sftp:connect-program "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Connect to Kinsta
open sftp://$KINSTA_USERNAME:$KINSTA_PASSWORD@$KINSTA_HOST_IP:$KINSTA_PORT

# Check if main MU plugin file exists
cd $remote_mu_plugin_path
ls -la kinsta-mu-plugins.php || echo "Main plugin file not found"
ls -la kinsta-mu-plugins/ || echo "Plugin directory not found"

quit
EOF

    if lftp -f "$lftp_check_script" 2>/dev/null | grep -q "kinsta-mu-plugins"; then
        log_success "MU Plugin installation validated successfully"
    else
        log_warning "Could not validate MU Plugin installation"
    fi
    
    rm -f "$lftp_check_script"
}

# Main execution function
main() {
    local target_path="${TARGET_PATH}"
    local mu_plugin_path="${KINSTA_MU_PLUGIN_PATH:-wp-content/mu-plugins}"
    local dry_run="${DRY_RUN:-false}"
    local verbose="${VERBOSE:-false}"
    local install_plugin="${INSTALL_KINSTA_MU_PLUGIN:-true}"
    
    # Check if installation is enabled
    if [ "$install_plugin" != "true" ]; then
        log "Kinsta MU Plugin installation is disabled"
        return 0
    fi
    
    # Validate required environment variables for sFTP
    if [ "$dry_run" != "true" ]; then
        local missing_vars=()
        
        if [ -z "$KINSTA_HOST_IP" ]; then missing_vars+=("KINSTA_HOST_IP"); fi
        if [ -z "$KINSTA_USERNAME" ]; then missing_vars+=("KINSTA_USERNAME"); fi
        if [ -z "$KINSTA_PASSWORD" ]; then missing_vars+=("KINSTA_PASSWORD"); fi
        if [ -z "$KINSTA_PORT" ]; then missing_vars+=("KINSTA_PORT"); fi
        
        if [ ${#missing_vars[@]} -ne 0 ]; then
            log_error "Missing required sFTP environment variables: ${missing_vars[*]}"
            return 1
        fi
    fi
    
    # Install the MU plugin
    if install_kinsta_mu_plugin "$target_path" "$mu_plugin_path" "$dry_run" "$verbose"; then
        if [ "$dry_run" != "true" ]; then
            validate_mu_plugin_installation "$target_path/$mu_plugin_path" "$verbose"
        fi
        log_success "Kinsta MU Plugin installation completed"
    else
        log_error "Kinsta MU Plugin installation failed"
        return 1
    fi
}

# Run if script is executed directly
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
