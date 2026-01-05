#!/bin/bash

###############################################
# Script: create_ec2_dynamic.sh
# Purpose: Automate EC2 instance creation using dynamic queries
# Author: [Your Name]
###############################################

# Source the logger
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logger.sh"

set -euo pipefail  # Exit on any error, unset variable usage, and catch pipe failures

# Configurable Variables
INSTANCE_TYPE="${INSTANCE_TYPE:-t2.micro}"  # default if not set
REGION="${REGION:-eu-central-1}"           # default region
TAG_PROJECT="${TAG_PROJECT:-AutomationLab}" 

log_info "=========================================="
log_info "EC2 Instance Creation Script Started"
log_info "=========================================="

# Error handler
error_exit() {
    log_error "$1"
    exit 1
}

###############################################
# Step 1: Determine latest Amazon Linux 2 AMI
###############################################
log_info "[1/5] Retrieving latest Amazon Linux 2 AMI in ${REGION}..."
AMI_ID=$(aws ec2 describe-images \
    --region "${REGION}" \
    --owners amazon \
    --filters "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" "Name=state,Values=available" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text 2>/dev/null)

[[ -n "$AMI_ID" ]] || error_exit "Failed to find an Amazon Linux 2 AMI in ${REGION}"
log_info "✓ Latest AMI found: ${AMI_ID}"

###############################################
# Step 2: Create a unique Key Pair
###############################################
KEY_NAME="automation-lab-key-$(date +%s)"
log_info "[2/5] Creating key pair: ${KEY_NAME}"

aws ec2 create-key-pair \
    --key-name "${KEY_NAME}" \
    --region "${REGION}" \
    --query 'KeyMaterial' \
    --output text > "${KEY_NAME}.pem" 2>/dev/null || error_exit "Failed to create key pair"

chmod 400 "${KEY_NAME}.pem" || error_exit "Failed to set permissions on ${KEY_NAME}.pem"
log_info "✓ Key pair created and saved to ${KEY_NAME}.pem"

###############################################
# Step 3: Get or create security group
###############################################
SG_NAME="${SG_NAME:-devops-sg}"
log_info "[3/5] Checking for security group: ${SG_NAME}"

SG_ID=$(aws ec2 describe-security-groups \
    --region "${REGION}" \
    --filters "Name=group-name,Values=${SG_NAME}" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "")

if [[ -z "$SG_ID" || "$SG_ID" == "None" ]]; then
    log_warn "Security group '${SG_NAME}' not found, creating new one..."
    
    # Get default VPC
    VPC_ID=$(aws ec2 describe-vpcs \
        --region "${REGION}" \
        --filters "Name=isDefault,Values=true" \
        --query 'Vpcs[0].VpcId' \
        --output text 2>/dev/null)
    
    [[ -n "$VPC_ID" && "$VPC_ID" != "None" ]] || error_exit "Failed to find default VPC"

    SG_ID=$(aws ec2 create-security-group \
        --group-name "${SG_NAME}" \
        --description "AutomationLab security group" \
        --vpc-id "${VPC_ID}" \
        --region "${REGION}" \
        --query 'GroupId' \
        --output text 2>/dev/null)

    [[ -n "$SG_ID" ]] || error_exit "Failed to create security group"

    # Add SSH and HTTP rules
    for PORT in 22 80; do
        aws ec2 authorize-security-group-ingress \
            --group-id "$SG_ID" \
            --protocol tcp \
            --port "$PORT" \
            --cidr 0.0.0.0/0 >/dev/null 2>&1 \
            && log_info "✓ Port $PORT enabled in ${SG_NAME}" \
            || log_warn "Port $PORT may already exist"
    done
fi

log_info "✓ Using security group: ${SG_ID}"

###############################################
# Step 4: Launch EC2 Instance
###############################################
log_info "[4/5] Launching EC2 instance..."
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "${AMI_ID}" \
    --instance-type "${INSTANCE_TYPE}" \
    --key-name "${KEY_NAME}" \
    --security-group-ids "${SG_ID}" \
    --region "${REGION}" \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=AutomationLabInstance},{Key=Project,Value=${TAG_PROJECT}}]" \
    --query 'Instances[0].InstanceId' \
    --output text 2>/dev/null)

[[ -n "$INSTANCE_ID" ]] || error_exit "Failed to launch EC2 instance"
log_info "✓ Instance launched: ${INSTANCE_ID}"

# Wait until running
log_info "Waiting for instance to be running..."
aws ec2 wait instance-running --region "${REGION}" --instance-ids "${INSTANCE_ID}" 2>/dev/null || error_exit "Instance failed to reach running state"

# Get public and private IPs
PUBLIC_IP=$(aws ec2 describe-instances \
    --region "${REGION}" \
    --instance-ids "${INSTANCE_ID}" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text 2>/dev/null || echo "N/A")

PRIVATE_IP=$(aws ec2 describe-instances \
    --region "${REGION}" \
    --instance-ids "${INSTANCE_ID}" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text 2>/dev/null || echo "N/A")

[[ "$PUBLIC_IP" == "None" ]] && PUBLIC_IP="N/A"

###############################################
# Step 5: Display results and save info
###############################################
log_info ""
log_info "=========================================="
log_info "EC2 Instance Created Successfully!"
log_info "=========================================="
log_info "Instance ID: ${INSTANCE_ID}"
log_info "Region: ${REGION}"
log_info "Public IP: ${PUBLIC_IP}"
log_info "Private IP: ${PRIVATE_IP}"
log_info "Key Pair: ${KEY_NAME}.pem"
log_info "Security Group: ${SG_ID}"

if [ "$PUBLIC_IP" != "N/A" ]; then
    log_info "SSH Command: ssh -i ${KEY_NAME}.pem ec2-user@${PUBLIC_IP}"
else
    log_info "SSH Command: ssh -i ${KEY_NAME}.pem ec2-user@${PRIVATE_IP} (requires VPN/bastion)"
fi

# Save instance info
cat > ec2_instance_info.txt <<EOF
Instance ID: ${INSTANCE_ID}
Region: ${REGION}
Public IP: ${PUBLIC_IP}
Private IP: ${PRIVATE_IP}
Key Pair: ${KEY_NAME}.pem
Security Group: ${SG_ID}
Instance Type: ${INSTANCE_TYPE}
AMI ID: ${AMI_ID}
Created: $(date)
EOF

log_info "Instance information saved to ec2_instance_info.txt"

# Optional: display instance summary
aws ec2 describe-instances \
    --region "${REGION}" \
    --instance-ids "${INSTANCE_ID}" \
    --query 'Reservations[0].Instances[0].[InstanceId,State.Name,InstanceType,PublicIpAddress,PrivateIpAddress]' \
    --output table

log_info "Script completed successfully"
