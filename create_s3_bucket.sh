#!/bin/bash

###############################################
# Script: create_s3_bucket.sh
# Purpose: Create S3 bucket with versioning
# Author: [Your Name]
###############################################

# Source the logger
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logger.sh"

set -e

# Configuration
# Clean username: remove special characters and ensure lowercase
CLEAN_USER=$(whoami | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')
BUCKET_NAME="automation-lab-bucket-$(date +%s)-${CLEAN_USER}"
REGION="eu-central-1"
SAMPLE_FILE="welcome.txt"

log_info "=========================================="
log_info "S3 Bucket Creation Script Started"
log_info "=========================================="

# Error handler
error_exit() {
    log_error "$1"
    exit 1
}

# Validate bucket name (S3 naming rules)
validate_bucket_name() {
    local name="$1"
    
    # Check length (3-63 characters)
    if [ ${#name} -lt 3 ] || [ ${#name} -gt 63 ]; then
        error_exit "Bucket name must be between 3 and 63 characters"
    fi
    
    # Check for valid characters (lowercase, numbers, hyphens)
    if ! [[ "$name" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]]; then
        error_exit "Bucket name contains invalid characters. Only lowercase letters, numbers, and hyphens allowed"
    fi
    
    # Check for consecutive hyphens
    if [[ "$name" =~ -- ]]; then
        error_exit "Bucket name cannot contain consecutive hyphens"
    fi
    
    log_debug "Bucket name validation passed: ${name}"
}

# Validate the bucket name before proceeding
validate_bucket_name "${BUCKET_NAME}"

# Step 1: Create bucket
log_info "[1/5] Creating S3 bucket: ${BUCKET_NAME}"
log_debug "Region: ${REGION}"

# Handle us-east-1 special case
if [ "$REGION" == "us-east-1" ]; then
    aws s3api create-bucket \
        --bucket "${BUCKET_NAME}" \
        --region "${REGION}" 2>/dev/null || error_exit "Failed to create bucket in us-east-1"
else
    aws s3api create-bucket \
        --bucket "${BUCKET_NAME}" \
        --region "${REGION}" \
        --create-bucket-configuration LocationConstraint="${REGION}" 2>/dev/null || error_exit "Failed to create bucket in ${REGION}"
fi

log_info "✓ Bucket created: ${BUCKET_NAME}"

# Step 2: Enable versioning
log_info "[2/5] Enabling versioning"
aws s3api put-bucket-versioning \
    --bucket "${BUCKET_NAME}" \
    --versioning-configuration Status=Enabled 2>/dev/null || error_exit "Failed to enable versioning"

log_info "✓ Versioning enabled"

# Step 3: Add bucket tags
log_info "[3/5] Adding tags"
aws s3api put-bucket-tagging \
    --bucket "${BUCKET_NAME}" \
    --tagging 'TagSet=[{Key=Project,Value=AutomationLab},{Key=Environment,Value=Development}]' 2>/dev/null || log_warn "Failed to add tags (non-critical)"

log_info "✓ Tags added (Project=AutomationLab, Environment=Development)"

# Step 4: Create sample file
log_info "[4/5] Creating sample file"
cat > "${SAMPLE_FILE}" <<EOF
Welcome to the Automation Lab!
This file was uploaded by an automated script.
Created: $(date)
Bucket: ${BUCKET_NAME}
Region: ${REGION}
User: ${CLEAN_USER}
EOF

log_info "✓ Sample file created: ${SAMPLE_FILE}"

# Step 5: Upload file to bucket
log_info "[5/5] Uploading file to S3"
aws s3 cp "${SAMPLE_FILE}" "s3://${BUCKET_NAME}/${SAMPLE_FILE}" 2>/dev/null || error_exit "Failed to upload file to S3"

log_info "✓ File uploaded: s3://${BUCKET_NAME}/${SAMPLE_FILE}"

# Display bucket information
log_info ""
log_info "=========================================="
log_info "S3 Bucket Created Successfully!"
log_info "=========================================="
log_info "Bucket Name: ${BUCKET_NAME}"
log_info "Region: ${REGION}"
log_info "Versioning: Enabled"
log_info "Sample File: ${SAMPLE_FILE}"
log_info ""
log_info "To download the file:"
log_info "  aws s3 cp s3://${BUCKET_NAME}/${SAMPLE_FILE} ."
log_info ""
log_info "To list bucket contents:"
log_info "  aws s3 ls s3://${BUCKET_NAME}/"
log_info ""
log_info "To view file in browser:"
log_info "  https://${BUCKET_NAME}.s3.${REGION}.amazonaws.com/${SAMPLE_FILE}"
log_info "=========================================="

# Save bucket name
echo "${BUCKET_NAME}" > s3_bucket_name.txt
log_info "Bucket name saved to s3_bucket_name.txt"
log_info "Script completed successfully"