#!/usr/bin/env bash

###############################################
# lib/common.sh
# Shared utility functions for all scripts
# Purpose: DRY principle — centralize repeated patterns
###############################################

set -euo pipefail

# ================================================
# ARGUMENT PARSING
# ================================================

# parse_dry_run_flag: Extract --dry-run from args and set DRY_RUN variable
# Usage: parse_dry_run_flag "$@"
parse_dry_run_flag() {
    DRY_RUN="false"
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run|--dry)
                DRY_RUN="true"
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [--dry-run]"
                echo "  --dry-run, --dry   Preview actions without making changes"
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                exit 1
                ;;
        esac
    done
    export DRY_RUN
}

# ================================================
# GUARD CHECKS
# ================================================

# check_command: Verify command exists, exit if missing
# Usage: check_command "aws" "AWS CLI"
check_command() {
    local cmd="$1"
    local name="${2:-$cmd}"
    command -v "$cmd" >/dev/null || { 
        log_error "$name required"
        exit 1
    }
}

# check_aws_credentials: Verify AWS CLI is configured
check_aws_credentials() {
    aws sts get-caller-identity >/dev/null || {
        log_error "AWS credentials missing or invalid"
        exit 1
    }
}

# check_dependencies: Verify all required commands exist
# Usage: check_dependencies "aws" "jq" "sed"
check_dependencies() {
    local missing=()
    for cmd in "$@"; do
        command -v "$cmd" >/dev/null || missing+=("$cmd")
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing[*]}"
        exit 1
    fi
}

# ================================================
# STATE MANAGEMENT SETUP
# ================================================

# init_state: Initialize and pull state (combines state_init + state_pull)
# Usage: init_state
init_state() {
    state_init
    state_pull
}

# ================================================
# INPUT PROMPTS
# ================================================

# prompt_cidr: Prompt user for CIDR block (with examples)
# Usage: prompt_cidr "SSH" "203.0.113.0/24 or 0.0.0.0/0"
prompt_cidr() {
    local purpose="$1"
    local examples="${2:-203.0.113.0/24 or 0.0.0.0/0}"
    local cidr=""
    
    read -rp "Enter CIDR block for $purpose access (e.g., $examples): " cidr
    while [[ -z "$cidr" ]]; do
        log_error "CIDR block cannot be empty"
        read -rp "Enter CIDR block for $purpose access (e.g., $examples): " cidr
    done
    
    echo "$cidr"
}

# get_cidr_or_env: Get CIDR from environment variable or prompt user
# Usage: SSH_CIDR=$(get_cidr_or_env "SSH_CIDR" "SSH")
get_cidr_or_env() {
    local env_var="$1"
    local purpose="$2"
    local value="${!env_var:-}"
    
    if [[ -z "$value" ]]; then
        echo ""
        value=$(prompt_cidr "$purpose")
        log_info "${purpose} CIDR set to: $value"
    fi
    
    echo "$value"
}

# ================================================
# LOGGING & FORMATTING
# ================================================

# print_header: Print a standard section header
# Usage: print_header "Creating Resources"
print_header() {
    local title="$1"
    log_info "=========================================="
    log_info "$title"
    log_info "=========================================="
}

# print_footer: Print a standard section footer
# Usage: print_footer "Operation Complete"
print_footer() {
    local title="$1"
    log_info "=========================================="
    log_info "$title"
    log_info "=========================================="
}

# print_dryrun_header: Print dry-run header
print_dryrun_header() {
    log_dryrun ""
    log_dryrun "==================== DRY-RUN ===================="
}

# print_dryrun_footer: Print dry-run footer
print_dryrun_footer() {
    log_dryrun "=================================================="
    log_dryrun "No resources will be created in dry-run mode."
}

# ================================================
# EXIT HELPERS
# ================================================

# exit_dryrun: Exit cleanly after dry-run display
exit_dryrun() {
    print_dryrun_footer
    exit 0
}

# ================================================
# BANNER PRINTING
# ================================================

# print_dry_run_notice: Print standard dry-run notice at startup
# Usage: [[ "$DRY_RUN" == "true" ]] && print_dry_run_notice
print_dry_run_notice() {
    log_warn "DRY-RUN MODE ENABLED"
}

