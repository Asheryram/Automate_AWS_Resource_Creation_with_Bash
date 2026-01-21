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
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        log_error "❌ AWS credentials are invalid or missing"
        log_error ""
        log_error "Fix with: aws configure"
        log_error ""
        log_error "You'll need:"
        log_error "  - AWS Access Key ID"
        log_error "  - AWS Secret Access Key"
        log_error "  - Default region (e.g., eu-central-1)"
        log_error ""
        log_error "Or set environment variables:"
        log_error "  export AWS_ACCESS_KEY_ID=your_access_key"
        log_error "  export AWS_SECRET_ACCESS_KEY=your_secret_key"
        exit 1
    fi
}

# check_aws_region: Verify AWS region format is valid
# Usage: check_aws_region "eu-central-1"
check_aws_region() {
    local region="${1:-}"
    
    # If region is empty, try to get from aws config
    if [[ -z "$region" ]]; then
        region=$(aws configure get region 2>/dev/null || echo "")
    fi
    
    # If still empty, use default
    if [[ -z "$region" ]]; then
        region="eu-central-1"
    fi
    
    # Validate region format (e.g., us-east-1, eu-central-1)
    if [[ ! "$region" =~ ^[a-z]{2,}-[a-z]+-[0-9]$ ]]; then
        log_error "❌ Invalid AWS region: '$region'"
        log_error ""
        log_error "Region must be in format: AREA-NAME-NUMBER"
        log_error "Examples:"
        log_error "  ✓ eu-central-1   (Europe - Central)"
        log_error "  ✓ eu-west-1      (Europe - West)"
        log_error "  ✓ us-east-1      (US - East)"
        log_error "  ✓ us-west-2      (US - West)"
        log_error "  ✗ eu             (NOT VALID - missing name and number)"
        log_error ""
        log_error "Fix with: aws configure set region eu-central-1"
        exit 1
    fi
    
    # Export region for use in scripts
    export AWS_REGION="$region"
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
