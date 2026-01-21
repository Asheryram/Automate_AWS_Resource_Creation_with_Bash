#!/usr/bin/env bash
set -euo pipefail

###############################################
# Script: create_security_group.sh
# Purpose: Create and configure security group using state manager
# Author: [Your Name]
###############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logger.sh"
source "${SCRIPT_DIR}/state_manager.sh"

# Parse arguments
DRY_RUN=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run|--dry)
            DRY_RUN=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--dry-run]"
            echo "  --dry-run, --dry   Preview actions without making changes"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Configuration
SG_NAME="devops-sg"

log_info "=========================================="
log_info "Security Group Creation Script Started"
[[ "$DRY_RUN" == "true" ]] && log_warn "DRY-RUN MODE: No changes will be made"
log_info "=========================================="

# Initialize state backend
state_init

# Check if the SG already exists in state
EXISTING_SG_ID=$(jq -r ".resources.security_group | to_entries[] | select(.value.name==\"$SG_NAME\") | .key" "$STATE_LOCAL" 2>/dev/null || echo "")

if [[ -n "$EXISTING_SG_ID" ]]; then
    log_info "Security group '$SG_NAME' already exists in state: $EXISTING_SG_ID"
    exit 0
fi

# Dry-run summary
if [[ "$DRY_RUN" == "true" ]]; then
    log_info ""
    log_info "DRY-RUN SUMMARY"
    log_info "=========================================="
    log_info "Would create security group: $SG_NAME"
    log_info "Would add ingress rules: SSH(22) + HTTP(80)"
    log_info "Would track SG in remote state"
    log_info "=========================================="
    exit 0
fi

# Create the security group
SG_ID=$(sg_create "$SG_NAME")

# Add default ingress rules
log_info "Adding SSH (22) and HTTP (80) rules to $SG_NAME"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr 0.0.0.0/0 >/dev/null 2>&1 || log_warn "SSH rule may already exist"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 >/dev/null 2>&1 || log_warn "HTTP rule may already exist"

# Display SG details
log_info ""
log_info "=========================================="
log_info "Security Group Created Successfully!"
log_info "Security Group Name: $SG_NAME"
log_info "Security Group ID: $SG_ID"
log_info "Inbound Rules:"
aws ec2 describe-security-groups --group-ids "$SG_ID" --query 'SecurityGroups[0].IpPermissions' --output table
log_info "=========================================="

log_info "Security group tracked in state backend"
