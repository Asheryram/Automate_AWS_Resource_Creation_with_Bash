#!/usr/bin/env bash

###############################################
# lib/checks.sh
# Dependency and credential checking
###############################################

set -euo pipefail

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
