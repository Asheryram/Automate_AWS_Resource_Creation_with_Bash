#!/usr/bin/env bash
set -euo pipefail

###############################################
# Script: create_security_group.sh
# Purpose: Create and configure security group using state manager
###############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logger.sh"
source "${SCRIPT_DIR}/lib/args.sh"
source "${SCRIPT_DIR}/lib/checks.sh"
source "${SCRIPT_DIR}/lib/prompts.sh"
source "${SCRIPT_DIR}/lib/output.sh"
source "${SCRIPT_DIR}/lib/state.sh"
source "${SCRIPT_DIR}/state/state_manager.sh"

# Parse arguments & check dependencies
parse_dry_run_flag "$@"
check_dependencies "aws" "jq"

# Configuration
SG_NAME="devops-sg"
SSH_CIDR=$(get_cidr_or_env "SSH_CIDR" "SSH")
HTTP_CIDR=$(get_cidr_or_env "HTTP_CIDR" "HTTP")

print_header "Security Group Creation Script"
[[ "$DRY_RUN" == "true" ]] && print_dry_run_notice

# Initialize state backend
init_state

# Check if the SG already exists in state
EXISTING_SG_ID=$(jq -r ".resources.security_group | to_entries[] | select(.value.name==\"$SG_NAME\") | .key" "$STATE_LOCAL" 2>/dev/null || echo "")

if [[ -n "$EXISTING_SG_ID" ]]; then
    log_info "Security group '$SG_NAME' already exists in state: $EXISTING_SG_ID"
    exit 0
fi

# Dry-run summary
if [[ "$DRY_RUN" == "true" ]]; then
    print_dryrun_header
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
    print_dryrun_footer
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
print_footer "Security Group Created Successfully"
log_info "Security Group Name: $SG_NAME"
log_info "Security Group ID: $SG_ID"
log_info "Inbound Rules:"
aws ec2 describe-security-groups --group-ids "$SG_ID" --query 'SecurityGroups[0].IpPermissions' --output table
print_footer "Setup Complete"

log_info "Security group tracked in state backend"
