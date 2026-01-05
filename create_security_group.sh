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

# Configuration
SG_NAME="devops-sg"
SG_DESCRIPTION="Security group for DevOps automation lab"
VPC_ID=""  # Leave empty to use default VPC

log_info "=========================================="
log_info "Security Group Creation Script Started"
log_info "=========================================="

# Error handler
error_exit() {
    log_error "$1"
    exit 1
}

###############################################
# Step 1: Get VPC ID
###############################################
if [ -z "$VPC_ID" ]; then
    log_info "[1/5] Getting default VPC"
    VPC_ID=$(aws ec2 describe-vpcs \
        --filters "Name=isDefault,Values=true" \
        --query 'Vpcs[0].VpcId' \
        --output text 2>/dev/null)

    [[ -n "$VPC_ID" && "$VPC_ID" != "None" ]] || error_exit "Could not find default VPC"
    log_info "✓ Using VPC: ${VPC_ID}"
fi

###############################################
# Step 2: Check if security group exists
###############################################
log_info "[2/5] Checking if security group exists"
EXISTING_SG=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=${SG_NAME}" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "None")

if [ "$EXISTING_SG" != "None" ]; then
    log_warn "Security group '${SG_NAME}' already exists with ID: ${EXISTING_SG}"
    read -rp "Do you want to delete and recreate it? (yes/no) " response
    [[ "$response" == "yes" ]] || { log_info "Exiting without changes"; exit 0; }

    log_info "Deleting existing security group..."
    aws ec2 delete-security-group --group-id "${EXISTING_SG}" 2>/dev/null \
        && log_info "✓ Deleted existing security group" \
        || error_exit "Failed to delete existing security group (may be in use)"
fi

###############################################
# Step 3: Create security group
###############################################
log_info "[3/5] Creating security group: ${SG_NAME}"
SG_ID=$(aws ec2 create-security-group \
    --group-name "${SG_NAME}" \
    --description "${SG_DESCRIPTION}" \
    --vpc-id "${VPC_ID}" \
    --query 'GroupId' \
    --output text 2>/dev/null)

[[ -n "$SG_ID" ]] || error_exit "Failed to create security group"
log_info "✓ Security group created: ${SG_ID}"

###############################################
# Step 4: Add SSH rule (port 22)
###############################################
log_info "[4/5] Adding SSH ingress rule (port 22)"
aws ec2 authorize-security-group-ingress \
    --group-id "${SG_ID}" \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0 2>/dev/null \
    && log_info "✓ SSH access enabled (0.0.0.0/0)" \
    || log_warn "Failed to add SSH rule (may already exist)"

###############################################
# Step 5: Add HTTP rule (port 80)
###############################################
log_info "[5/5] Adding HTTP ingress rule (port 80)"
aws ec2 authorize-security-group-ingress \
    --group-id "${SG_ID}" \
    --protocol tcp \
    --port 80 \
    --cidr 0.0.0.0/0 2>/dev/null \
    && log_info "✓ HTTP access enabled (0.0.0.0/0)" \
    || log_warn "Failed to add HTTP rule (may already exist)"

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
log_info "Inbound Rules:"

aws ec2 describe-security-groups \
    --group-ids "${SG_ID}" \
    --query 'SecurityGroups[0].IpPermissions' \
    --output table

log_info "=========================================="

# Step 7: Save to file
echo "${SG_ID}" > security_group_id.txt
log_info "Security group ID saved to security_group_id.txt"
log_info "Script completed successfully"
