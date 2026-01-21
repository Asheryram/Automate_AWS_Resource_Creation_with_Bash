#!/usr/bin/env bash

###############################################
# lib/prompts.sh
# User input prompts and interactive utilities
###############################################

set -euo pipefail

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
