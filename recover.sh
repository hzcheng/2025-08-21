#!/bin/bash
set -euo pipefail

# Global configurations
readonly ROOT_DIR="/root/workspace/support/2025-08-21"
readonly TD_ROOT_DIR="${ROOT_DIR}/dnode"
readonly TAOSD="/root/workspace/TDinternal/debug/build/bin/taosd"
readonly TAOS="/root/workspace/TDinternal/debug/build/bin/taos"

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

function start_taosd_process() {
    local cfg_dir=""
    local background=true
    local timeout=30
    
    # Parse parameters
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cfg_dir=*)
                cfg_dir="${1#*=}"
                shift
                ;;
            --foreground)
                background=false
                shift
                ;;
            --timeout=*)
                timeout="${1#*=}"
                shift
                ;;
            *)
                log_error "Unknown parameter: $1"
                return 1
                ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "$cfg_dir" ]]; then
        log_error "Missing required parameter: --cfg_dir"
        log_error "Usage: start_taosd_process --cfg_dir=<path> [--foreground] [--timeout=<seconds>]"
        return 1
    fi
    
    local config_file="$cfg_dir/taos.cfg"
    
    # Validate configuration file exists
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        return 1
    fi
    
    # Validate TDengine executable exists and is executable
    if [[ ! -x "$TAOSD" ]]; then
        log_error "TDengine executable not found or not executable: $TAOSD"
        return 1
    fi
    
    # Check if taosd is already running
    local existing_pid
    existing_pid=$(pgrep -f taosd) || true
    if [[ -n "$existing_pid" ]]; then
        log_warn "TDengine server is already running (PID: ${WHITE}$existing_pid${NC})"
        return 0
    fi
    
    log_info "Starting TDengine server..."
    log_info "  • Executable: ${CYAN}$TAOSD${NC}"
    log_info "  • Config file: ${CYAN}$config_file${NC}"
    log_info "  • Background mode: ${WHITE}$background${NC}"
    
    if [[ "$background" == true ]]; then
        # Start in background
        "$TAOSD" -c "$config_file" > /dev/null 2>&1 &
        local taosd_pid=$!
        
        log_info "TDengine server started in background (PID: ${WHITE}$taosd_pid${NC})"
        
        # Wait for server to be ready with timeout
        log_info "Waiting for TDengine server to be ready (timeout: ${timeout}s)..."
        local wait_count=0
        local ready=false
        
        while [[ $wait_count -lt $timeout ]]; do
            # Check if process is still running
            if ! kill -0 "$taosd_pid" 2>/dev/null; then
                log_error "TDengine server process died unexpectedly"
                return 1
            fi
            
            # Try to connect to check if server is ready
            if ASAN_OPTIONS=detect_odr_violation=0 "$TAOS" -c "$config_file" -s "SELECT SERVER_VERSION();" >/dev/null 2>&1; then
                ready=true
                break
            fi
            
            sleep 1
            ((wait_count++))
            
            # Log progress every 5 seconds
            if [[ $((wait_count % 5)) -eq 0 ]]; then
                log_info "Still waiting for server to be ready... (${wait_count}s elapsed)"
            fi
        done
        
        if [[ "$ready" == true ]]; then
            log_success "TDengine server is ready and accepting connections"
            # Store PID in global variable for cleanup
            export TAOSD_PID="$taosd_pid"
        else
            log_error "TDengine server failed to become ready within ${timeout}s"
            kill "$taosd_pid" 2>/dev/null || true
            return 1
        fi
    else
        # Start in foreground
        log_info "Starting TDengine server in foreground mode..."
        "$TAOSD" -c "$config_file"
    fi
}

function kill_taosd_process() {
    local pid
    
    pid=$(pgrep -f taosd) || true
    if [[ -n "$pid" ]]; then
        log_info "Stopping taosd process with SIGTERM (PID: ${WHITE}$pid${NC})..."
        kill -TERM "$pid" || true
        
        # Wait for graceful shutdown with warnings every 5 seconds
        local wait_count=0
        local total_wait=0
        while kill -0 "$pid" 2>/dev/null; do
            sleep 5
            ((wait_count++))
            total_wait=$((wait_count * 5))
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

function generate_cfg_file() {
    local cfg_dir=""
    local data_dir=""
    local log_dir=""
    
    # Parse parameters
    while [[ $# -gt 0 ]]; do
        case $1 in
            --cfg_dir=*)
                cfg_dir="${1#*=}"
                shift
                ;;
            --data_dir=*)
                data_dir="${1#*=}"
                shift
                ;;
            --log_dir=*)
                log_dir="${1#*=}"
                shift
                ;;
            *)
                log_error "Unknown parameter: $1"
                return 1
                ;;
        esac
    done
    
    # Validate required parameters
    if [[ -z "$cfg_dir" || -z "$data_dir" || -z "$log_dir" ]]; then
        log_error "Missing required parameters for generate_cfg_file"
        log_error "Usage: generate_cfg_file --cfg_dir=<path> --data_dir=<path> --log_dir=<path>"
        return 1
    fi
    
    local config_file="$cfg_dir/taos.cfg"
    
    log_info "Generating TDengine configuration file: ${CYAN}$config_file${NC}"
    
    # Generate comprehensive TDengine configuration
    cat <<EOF > "$config_file"
# TDengine Configuration File
# Generated by recovery script on $(date)

# Basic Settings
fqdn                    localhost
port                    6030
serverPort              6030

# Directory Settings  
dataDir                 $data_dir
logDir                  $log_dir
EOF

    if [[ -f "$config_file" ]]; then
        log_success "Configuration file generated successfully"
        log_info "Configuration details:"
        log_info "  • Data directory: ${CYAN}$data_dir${NC}"
        log_info "  • Log directory: ${CYAN}$log_dir${NC}"
        log_info "  • Config file: ${CYAN}$config_file${NC}"
    else
        log_error "Failed to generate configuration file"
        return 1
    fi
}

function create_database() {
    local vgroups=1
    
    # Parse parameters
    while [[ $# -gt 0 ]]; do
        case $1 in
            --vgroups=*)
                vgroups="${1#*=}"
                shift
                ;;
            *)
                log_error "Unknown parameter: $1"
                return 1
                ;;
        esac
    done
    
    if [[ -z "$vgroups" ]]; then
        log_error "Missing required parameter: --vgroups"
        return 1
    fi
    
    log_info "Creating database with $vgroups vgroups..."
    
    # Create database using TDengine CLI with ASAN options
    if ! ASAN_OPTIONS=detect_odr_violation=0 "$TAOS" -c ${TD_ROOT_DIR}/cfg -s "CREATE DATABASE yzs1 BUFFER 256 CACHESIZE 50 CACHEMODEL 'both' COMP 2 DURATION 14400m WAL_FSYNC_PERIOD 3000 MAXROWS 4096 MINROWS 100 STT_TRIGGER 2 KEEP 1080000m,1080000m,1080000m PAGES 256 PAGESIZE 4 PRECISION 'ms' REPLICA 1 WAL_LEVEL 1 VGROUPS $vgroups SINGLE_STABLE 0 TABLE_PREFIX 0 TABLE_SUFFIX 0 TSDB_PAGESIZE 4 WAL_RETENTION_PERIOD 3600 WAL_RETENTION_SIZE 0;"; then
        log_error "Failed to create database"
        return 1
    fi
    
    log_success "Database created successfully with $vgroups vgroups"
}

function create_recovery_environment() {
    local root_dir="$TD_ROOT_DIR"
    local cfg_dir="$root_dir/cfg"
    local data_dir="$root_dir/data"
    local log_dir="$root_dir/log"

    log_info "Creating directories for recovery environment..."
    mkdir -p "$cfg_dir" "$data_dir" "$log_dir"

    log_info "Generating configuration file..."
    generate_cfg_file --cfg_dir="$cfg_dir" --data_dir="$data_dir" --log_dir="$log_dir"

    log_info "Starting taosd process..."
    start_taosd_process --cfg_dir="$cfg_dir"

    sleep 5

    log_info "Creating database..."
    create_database --vgroups=12

    log_success "Recovery environment created successfully."
}

function main() {
    log_info "Step 0: Cleaning up old recovery environment..."
    cleanup_recovery_environment

    log_info "Step 1: Creating recovery environment..."
    create_recovery_environment

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