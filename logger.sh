#!/usr/bin/env bash
# simple_logger.sh - lightweight logging for AWS automation scripts

# Default log file (can be overridden)
LOG_FILE="${LOG_FILE:-./aws_project.log}"
CONSOLE_LOG="${CONSOLE_LOG:-true}"   # Whether to print to console
LOG_LEVEL="${LOG_LEVEL:-INFO}"       # Default level: DEBUG, INFO, WARN, ERROR

# Convert level to numeric value for comparison
level_to_num() {
    case "$1" in
        DEBUG) echo 1 ;;
        INFO)  echo 2 ;;
        WARN)  echo 3 ;;
        ERROR) echo 4 ;;
        *) echo 2 ;;  # default INFO
    esac
}

# Generic logging function
log_message() {
    local level="$1"
    local msg="$2"
    local level_num msg_level_num

    msg_level_num=$(level_to_num "$level")
    level_num=$(level_to_num "$LOG_LEVEL")

    # Skip if message level is less important than current LOG_LEVEL
    if (( msg_level_num < level_num )); then
        return
    fi

    # Timestamp
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Format message
    local log_entry="[$timestamp] [$level] $msg"

    # Print to console
    if [[ "$CONSOLE_LOG" == "true" ]]; then
        case "$level" in
            DEBUG) echo -e "\e[34m$log_entry\e[0m" ;;    # Blue
            INFO)  echo "$log_entry" ;;
            WARN)  echo -e "\e[33m$log_entry\e[0m" ;;    # Yellow
            ERROR) echo -e "\e[31m$log_entry\e[0m" ;;    # Red
            *) echo "$log_entry" ;;
        esac
    fi

    # Append to log file
    echo "$log_entry" >> "$LOG_FILE" 2>/dev/null
}

# Helper functions for each log level
log_debug() { log_message "DEBUG" "$1"; }
log_info()  { log_message "INFO"  "$1"; }
log_warn()  { log_message "WARN"  "$1"; }
log_error() { log_message "ERROR" "$1"; }
