#!/bin/bash
set -euo pipefail

# Global configurations
readonly ROOT_DIR="/root/workspace/support/2025-08-21"
readonly TD_ROOT_DIR="${ROOT_DIR}/dnode"

# Color definitions
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly WHITE='\033[1;37m'
readonly GRAY='\033[0;37m'
readonly NC='\033[0m' # No Color

# Function to log messages with timestamp and color
function log() {
    echo -e "${GRAY}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*"
}

# Function to log error messages
function log_error() {
    echo -e "${GRAY}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ${RED}ERROR:${NC} $*" >&2
}

# Function to log warning messages
function log_warn() {
    echo -e "${GRAY}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ${YELLOW}WARNING:${NC} $*" >&2
}

# Function to log info messages
function log_info() {
    echo -e "${GRAY}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ${BLUE}INFO:${NC} $*"
}

# Function to log success messages
function log_success() {
    echo -e "${GRAY}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} ${GREEN}SUCCESS:${NC} $*"
}

# function start_taosd_process() {
# }

function kill_taosd_process() {
    local pid
    
    pid=$(pgrep -f taosd) || true
    if [[ -n "$pid" ]]; then
        log_info "Stopping taosd process with SIGTERM (PID: ${WHITE}$pid${NC})..."
        kill -TERM "$pid"
        
        # Wait for graceful shutdown with warnings every 5 seconds
        local wait_count=0
        while kill -0 "$pid" 2>/dev/null; do
            sleep 5
            ((wait_count++))
            local total_wait=$((wait_count * 5))
            log_warn "Waiting for taosd process to terminate gracefully... (${total_wait}s elapsed)"
        done
        
        log_success "taosd process terminated gracefully after ${total_wait}s"
    else
        log_info "No taosd process found to kill"
    fi
}

function cleanup_recovery_environment() {
    # Kill taosd process
    kill_taosd_process

    # Remove the recovery folder
    local root_dir="$TD_ROOT_DIR"
    rm -rf "$root_dir"
    log_success "Recovery environment cleaned up successfully."
}

function create_recovery_environment() {
    local root_dir="$TD_ROOT_DIR"
    local cfg_dir="$root_dir/cfg"
    local data_dir="$root_dir/data"
    local log_dir="$root_dir/log"

    mkdir -p "$cfg_dir" "$data_dir" "$log_dir"
    log_success "Recovery environment created successfully."
}

function main() {
    # Step 0
    log_info "Cleaning up old recovery environment..."
    cleanup_recovery_environment

    # # Step 1
    # log_info "Creating recovery environment..."
    # create_recovery_environment

    # # Step 2
    # log_info "Mapping vnodes ..."

    # # Step 3
    # log_info "Starting recovery process..."
}

# Check if the script is being executed directly (not sourced)
# This prevents the main function from running when the script is sourced
# into another script, allowing for testing or library usage
# If true, execute the main function with all passed arguments
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

#     # Validate required files exist
#     if [[ ! -f "$V91_TAR_FILE" ]]; then
#         log_error "Required file not found: $V91_TAR_FILE"
#         exit 1
#     fi

#     cd "$ROOT_DIR"

#     # Kill any existing taosd processes
#     log_info "Stopping any existing taosd processes..."
#     pkill -f taosd || true
#     sleep 2

#     # Define TDengine paths and executables
#     TD_ROOT_DIR="${ROOT_DIR}/dnode"
#     TD_CONFIG_DIR="${TD_ROOT_DIR}/cfg"
#     TD_DATA_DIR="${TD_ROOT_DIR}/data"
#     TD_LOG_DIR="${TD_ROOT_DIR}/log"
#     TD_TAOSD="/root/workspace/TDinternal/debug/build/bin/taosd"
#     TD_TAOS="/root/workspace/TDinternal/debug/build/bin/taos"

#     # Validate TDengine executables exist
#     if [[ ! -x "$TD_TAOSD" ]]; then
#         log_error "taosd executable not found or not executable: $TD_TAOSD"
#         exit 1
#     fi

#     if [[ ! -x "$TD_TAOS" ]]; then
#         log_error "taos executable not found or not executable: $TD_TAOS"
#         exit 1
#     fi

#     # Setup TDengine directories
#     log_info "Setting up TDengine directories..."
#     rm -rf "$TD_ROOT_DIR"
#     mkdir -p "$TD_CONFIG_DIR" "$TD_DATA_DIR" "$TD_LOG_DIR"

#     # Create TDengine configuration file
#     CONFIG_FILE="${TD_CONFIG_DIR}/taos.cfg"
#     log_info "Creating configuration file: ${CYAN}$CONFIG_FILE${NC}"
#     cat <<EOF > "$CONFIG_FILE"
# fqdn localhost
# port 6030
# dataDir $TD_DATA_DIR
# logDir $TD_LOG_DIR
# EOF

#     # Start TDengine server
#     log_info "Starting TDengine server..."
#     "$TD_TAOSD" -c "$CONFIG_FILE" > /dev/null 2>&1 &
#     TAOSD_PID=$!
#     log_success "TDengine server started with PID: ${WHITE}$TAOSD_PID${NC}"

#     # Wait for server to be ready
#     log_info "Waiting for TDengine server to be ready..."
#     sleep 5

#     # Create database
#     log_info "Creating database ${PURPLE}yzs1${NC}..."
#     if ! ASAN_OPTIONS=detect_odr_violation=0 "$TD_TAOS" -c "$CONFIG_FILE" -s "CREATE DATABASE yzs1 BUFFER 256 CACHESIZE 50 CACHEMODEL 'both' COMP 2 DURATION 14400m WAL_FSYNC_PERIOD 3000 MAXROWS 4096 MINROWS 100 STT_TRIGGER 2 KEEP 1080000m,1080000m,1080000m PAGES 256 PAGESIZE 4 PRECISION 'ms' REPLICA 1 WAL_LEVEL 1 VGROUPS 1 SINGLE_STABLE 0 TABLE_PREFIX 0 TABLE_SUFFIX 0 TSDB_PAGESIZE 4 WAL_RETENTION_PERIOD 3600 WAL_RETENTION_SIZE 0;"; then
#         log_error "Failed to create database"
#         exit 1
#     fi
#     log_success "Database created successfully"

#     # Stop TDengine server
#     log_info "Stopping TDengine server..."
#     kill "$TAOSD_PID" && wait "$TAOSD_PID"
#     log_success "TDengine server stopped"

#     # Extract vnode data
#     log_info "Extracting vnode data from ${CYAN}$V91_TAR_FILE${NC}..."
#     rm -rf vnode91
#     if ! tar -zxvf "$V91_TAR_FILE"; then
#         log_error "Failed to extract $V91_TAR_FILE"
#         exit 1
#     fi

#     # Setup vnode symlink
#     VNODE_TARGET_DIR="$TD_DATA_DIR/vnode/vnode2/meta"
#     VNODE_SOURCE_FILE="$ROOT_DIR/vnode91/meta/main.tdb"

#     if [[ ! -f "$VNODE_SOURCE_FILE" ]]; then
#         log_error "Source file not found: $VNODE_SOURCE_FILE"
#         exit 1
#     fi

#     log_info "Setting up vnode symlink..."
#     rm -f "$VNODE_TARGET_DIR/main.tdb"
#     ln -s "$VNODE_SOURCE_FILE" "$VNODE_TARGET_DIR/main.tdb"

#     log_success "Recovery process completed successfully! 🎉"
