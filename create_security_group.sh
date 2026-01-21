#!/usr/bin/env bash
set -euo pipefail

###############################################
# Script: create_security_group.sh
# Purpose: Create and configure security group using state manager
# Author: [Your Name]
###############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logger.sh"
source "${SCRIPT_DIR}/state/state_manager.sh"

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
SSH_CIDR="${SSH_CIDR:-}"
HTTP_CIDR="${HTTP_CIDR:-}"

log_info "=========================================="
log_info "Security Group Creation Script Started"
[[ "$DRY_RUN" == "true" ]] && log_warn "DRY-RUN MODE: No changes will be made"
log_info "=========================================="

# ------------------------------------------------
# Get CIDR ranges if not provided
# ------------------------------------------------
if [[ -z "$SSH_CIDR" ]]; then
  echo ""
  read -rp "Enter CIDR block for SSH access (port 22) (e.g., 203.0.113.0/24 or 0.0.0.0/0 for anywhere): " SSH_CIDR
  while [[ -z "$SSH_CIDR" ]]; do
    log_error "CIDR block cannot be empty"
    read -rp "Enter CIDR block for SSH access (port 22) (e.g., 203.0.113.0/24 or 0.0.0.0/0 for anywhere): " SSH_CIDR
  done
  log_info "SSH CIDR set to: $SSH_CIDR"
fi

if [[ -z "$HTTP_CIDR" ]]; then
  echo ""
  read -rp "Enter CIDR block for HTTP access (port 80) (e.g., 203.0.113.0/24 or 0.0.0.0/0 for anywhere): " HTTP_CIDR
  while [[ -z "$HTTP_CIDR" ]]; do
    log_error "CIDR block cannot be empty"
    read -rp "Enter CIDR block for HTTP access (port 80) (e.g., 203.0.113.0/24 or 0.0.0.0/0 for anywhere): " HTTP_CIDR
  done
  log_info "HTTP CIDR set to: $HTTP_CIDR"
fi

# Initialize state backend
state_init
state_pull

# Check if the SG already exists in state
EXISTING_SG_ID=$(jq -r ".resources.security_group | to_entries[] | select(.value.name==\"$SG_NAME\") | .key" "$STATE_LOCAL" 2>/dev/null || echo "")

if [[ -n "$EXISTING_SG_ID" ]]; then
    log_info "Security group '$SG_NAME' already exists in state: $EXISTING_SG_ID"
    exit 0
fi

# Dry-run summary
if [[ "$DRY_RUN" == "true" ]]; then
    log_dryrun ""
    log_dryrun "==================== DRY-RUN ===================="
    log_dryrun "Resources that will be created:"
    log_dryrun ""
    log_dryrun "Security Group:"
    log_dryrun "  Name: $SG_NAME"
    log_dryrun "  Region: $AWS_REGION"
    log_dryrun ""
    log_dryrun "Ingress Rules:"
    log_dryrun "  - Protocol: TCP"
    log_dryrun "    Port: 22 (SSH)"
    log_dryrun "    CIDR: $SSH_CIDR"
    log_dryrun "  - Protocol: TCP"
    log_dryrun "    Port: 80 (HTTP)"
    log_dryrun "    CIDR: $HTTP_CIDR"
    log_dryrun ""
    log_dryrun "State Tracking:"
    log_dryrun "  Local State:  $STATE_LOCAL"
    log_dryrun "  Remote State: s3://$STATE_BUCKET/$STATE_KEY"
    log_dryrun ""
    log_dryrun "=================================================="
    log_dryrun "No resources will be created in dry-run mode."
    exit 0
fi

# Create the security group
SG_ID=$(sg_create "$SG_NAME")

# Add default ingress rules
log_info "Adding SSH (22) and HTTP (80) rules to $SG_NAME"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 22 --cidr "$SSH_CIDR" >/dev/null 2>&1 || log_warn "SSH rule may already exist"
aws ec2 authorize-security-group-ingress --group-id "$SG_ID" --protocol tcp --port 80 --cidr "$HTTP_CIDR" >/dev/null 2>&1 || log_warn "HTTP rule may already exist"

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
