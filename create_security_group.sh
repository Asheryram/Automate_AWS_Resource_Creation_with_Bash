#!/bin/bash

###############################################
# Script: create_security_group.sh
# Purpose: Create and configure security group
# Author: [Your Name]
###############################################

# Source the logger
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logger.sh"

set -e

# Parse command-line arguments
DRY_RUN="${DRY_RUN:-false}"  # Default from environment variable
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
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Configuration
SG_NAME="devops-sg"
SG_DESCRIPTION="Security group for DevOps automation lab"
VPC_ID=""  # Leave empty to use default VPC

log_info "=========================================="
log_info "Security Group Creation Script Started"
if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "DRY-RUN MODE: No changes will be made"
fi
log_info "=========================================="

# Error handler
error_exit() {
    log_error "$1"
    exit 1
}

# Guard: Check AWS CLI is installed
command -v aws >/dev/null 2>&1 || error_exit "AWS CLI is not installed. Please install it first."

# Guard: Check AWS credentials are configured
aws sts get-caller-identity >/dev/null 2>&1 || error_exit "AWS credentials not configured. Run 'aws configure' first."

# Guard: Validate security group name
[[ -n "$SG_NAME" ]] || error_exit "Security group name cannot be empty"
[[ "$SG_NAME" =~ ^[a-zA-Z0-9_-]+$ ]] || error_exit "Security group name contains invalid characters"

###############################################
# Step 1: Get VPC ID
###############################################
log_info "[1/5] Getting default VPC"

if [[ "$DRY_RUN" == "true" ]]; then
    log_dryrun "Would query for default VPC"
    VPC_ID="vpc-dry-run-example"
else
    if [ -z "$VPC_ID" ]; then
        VPC_ID=$(aws ec2 describe-vpcs \
            --filters "Name=isDefault,Values=true" \
            --query 'Vpcs[0].VpcId' \
            --output text 2>/dev/null)

        # Guard: VPC must exist
        [[ -n "$VPC_ID" && "$VPC_ID" != "None" ]] || error_exit "Could not find default VPC"
    fi
fi

log_info "✓ Using VPC: ${VPC_ID}"

###############################################
# Step 2: Check if security group exists
###############################################
log_info "[2/5] Checking if security group exists"

if [[ "$DRY_RUN" == "true" ]]; then
    log_dryrun "Would check for existing security group: ${SG_NAME}"
    EXISTING_SG="None"
else
    EXISTING_SG=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=${SG_NAME}" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "None")
fi

if [ "$EXISTING_SG" != "None" ]; then
    log_warn "Security group '${SG_NAME}' already exists with ID: ${EXISTING_SG}"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_dryrun "Would prompt to delete and recreate security group"
        log_dryrun "Assuming 'yes' for dry-run purposes"
    else
        read -rp "Do you want to delete and recreate it? (yes/no) " response
        [[ "$response" == "yes" ]] || { log_info "Exiting without changes"; exit 0; }

        log_info "Deleting existing security group..."
        aws ec2 delete-security-group --group-id "${EXISTING_SG}" 2>/dev/null \
            && log_info "✓ Deleted existing security group" \
            || error_exit "Failed to delete existing security group (may be in use)"
    fi
fi

###############################################
# Step 3: Create security group
###############################################
log_info "[3/5] Creating security group: ${SG_NAME}"

if [[ "$DRY_RUN" == "true" ]]; then
    log_dryrun "Would create security group with:"
    log_dryrun "  Name: ${SG_NAME}"
    log_dryrun "  Description: ${SG_DESCRIPTION}"
    log_dryrun "  VPC ID: ${VPC_ID}"
    SG_ID="sg-dry-run-example"
else
    SG_ID=$(aws ec2 create-security-group \
        --group-name "${SG_NAME}" \
        --description "${SG_DESCRIPTION}" \
        --vpc-id "${VPC_ID}" \
        --query 'GroupId' \
        --output text 2>/dev/null)

    # Guard: Security group creation must succeed
    [[ -n "$SG_ID" ]] || error_exit "Failed to create security group"
fi

log_info "✓ Security group created: ${SG_ID}"

###############################################
# Step 4: Add SSH rule (port 22)
###############################################
log_info "[4/5] Adding SSH ingress rule (port 22)"

if [[ "$DRY_RUN" == "true" ]]; then
    log_dryrun "Would add ingress rule:"
    log_dryrun "  Protocol: tcp"
    log_dryrun "  Port: 22"
    log_dryrun "  CIDR: 0.0.0.0/0"
else
    aws ec2 authorize-security-group-ingress \
        --group-id "${SG_ID}" \
        --protocol tcp \
        --port 22 \
        --cidr 0.0.0.0/0 2>/dev/null \
        && log_info "✓ SSH access enabled (0.0.0.0/0)" \
        || log_warn "Failed to add SSH rule (may already exist)"
fi

###############################################
# Step 5: Add HTTP rule (port 80)
###############################################
log_info "[5/5] Adding HTTP ingress rule (port 80)"

if [[ "$DRY_RUN" == "true" ]]; then
    log_dryrun "Would add ingress rule:"
    log_dryrun "  Protocol: tcp"
    log_dryrun "  Port: 80"
    log_dryrun "  CIDR: 0.0.0.0/0"
else
    aws ec2 authorize-security-group-ingress \
        --group-id "${SG_ID}" \
        --protocol tcp \
        --port 80 \
        --cidr 0.0.0.0/0 2>/dev/null \
        && log_info "✓ HTTP access enabled (0.0.0.0/0)" \
        || log_warn "Failed to add HTTP rule (may already exist)"
fi

###############################################
# Step 6: Display security group details
###############################################
log_info ""
log_info "=========================================="
log_info "Security Group Created Successfully!"
log_info "=========================================="
log_info "Security Group ID: ${SG_ID}"
log_info "Security Group Name: ${SG_NAME}"
log_info "VPC ID: ${VPC_ID}"
log_info ""

if [[ "$DRY_RUN" == "true" ]]; then
    log_dryrun "Would display inbound rules"
    log_dryrun "Expected rules:"
    log_dryrun "  - SSH (22) from 0.0.0.0/0"
    log_dryrun "  - HTTP (80) from 0.0.0.0/0"
else
    log_info "Inbound Rules:"
    aws ec2 describe-security-groups \
        --group-ids "${SG_ID}" \
        --query 'SecurityGroups[0].IpPermissions' \
        --output table
fi

log_info "=========================================="

# Step 7: Save to file
if [[ "$DRY_RUN" == "true" ]]; then
    log_dryrun "Would save security group ID to security_group_id.txt"
else
    echo "${SG_ID}" > security_group_id.txt
    log_info "Security group ID saved to security_group_id.txt"
fi

log_info "Script completed successfully"