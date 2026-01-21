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

# Parse command-line arguments
DRY_RUN="${DRY_RUN:-false}"
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
CLEAN_USER=$(whoami | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')
BUCKET_NAME="automation-lab-bucket-$(date +%s)-${CLEAN_USER}"
REGION="eu-central-1"
SAMPLE_FILE="welcome.txt"

log_info "=========================================="
log_info "S3 Bucket Creation Script Started"
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

# Guard: Validate region
[[ -n "$REGION" ]] || error_exit "Region cannot be empty"

# Validate bucket name (S3 naming rules)
validate_bucket_name() {
    local name="$1"
    
    [[ ${#name} -ge 3 ]] || error_exit "Bucket name must be at least 3 characters"
    [[ ${#name} -le 63 ]] || error_exit "Bucket name must be at most 63 characters"
    [[ "$name" =~ ^[a-z0-9][a-z0-9-]*[a-z0-9]$ ]] || error_exit "Bucket name contains invalid characters. Only lowercase letters, numbers, and hyphens allowed"
    [[ ! "$name" =~ -- ]] || error_exit "Bucket name cannot contain consecutive hyphens"
    
    log_debug "Bucket name validation passed: ${name}"
}

validate_bucket_name "${BUCKET_NAME}"

###############################################
# Dry-Run Summary Report
###############################################
if [[ "$DRY_RUN" == "true" ]]; then
    log_info ""
    log_info "DRY-RUN SUMMARY REPORT"
    log_info "=========================================="
    log_dryrun "Actions that would be performed:"
    log_dryrun ""
    log_dryrun "1. Create S3 bucket: ${BUCKET_NAME}"
    log_dryrun "   - Region: ${REGION}"
    log_dryrun "   - Configuration: LocationConstraint=${REGION}"
    log_dryrun ""
    log_dryrun "2. Enable versioning on bucket"
    log_dryrun ""
    log_dryrun "3. Apply tags:"
    log_dryrun "   - Project=AutomationLab"
    log_dryrun "   - Environment=Development"
    log_dryrun ""
    log_dryrun "4. Create local sample file: ${SAMPLE_FILE}"
    log_dryrun "   - Contains: Welcome message with metadata"
    log_dryrun ""
    log_dryrun "5. Upload ${SAMPLE_FILE} to s3://${BUCKET_NAME}/"
    log_dryrun ""
    log_dryrun "6. Save bucket name to s3_bucket_name.txt"
    log_dryrun ""
    log_dryrun "Expected output:"
    log_dryrun "  - Bucket URL: https://${BUCKET_NAME}.s3.${REGION}.amazonaws.com/${SAMPLE_FILE}"
    log_dryrun "  - Versioning: Enabled"
    log_info "=========================================="
    log_info "No actual resources created in dry-run mode"
    exit 0
fi

###############################################
# Step 1: Create bucket
###############################################
log_info "[1/5] Creating S3 bucket: ${BUCKET_NAME}"

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

###############################################
# Step 2: Enable versioning
###############################################
log_info "[2/5] Enabling versioning"

aws s3api put-bucket-versioning \
    --bucket "${BUCKET_NAME}" \
    --versioning-configuration Status=Enabled 2>/dev/null || error_exit "Failed to enable versioning"

log_info "✓ Versioning enabled"

###############################################
# Step 3: Add bucket tags
###############################################
log_info "[3/5] Adding tags"

aws s3api put-bucket-tagging \
    --bucket "${BUCKET_NAME}" \
    --tagging 'TagSet=[{Key=Project,Value=AutomationLab},{Key=Environment,Value=Development}]' 2>/dev/null || log_warn "Failed to add tags (non-critical)"

log_info "✓ Tags added (Project=AutomationLab, Environment=Development)"

###############################################
# Step 4: Create sample file
###############################################
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

###############################################
# Step 5: Upload file to bucket
###############################################
log_info "[5/5] Uploading file to S3"

[[ -f "${SAMPLE_FILE}" ]] || error_exit "Sample file ${SAMPLE_FILE} does not exist"

aws s3 cp "${SAMPLE_FILE}" "s3://${BUCKET_NAME}/${SAMPLE_FILE}" 2>/dev/null || error_exit "Failed to upload file to S3"

log_info "✓ File uploaded: s3://${BUCKET_NAME}/${SAMPLE_FILE}"

###############################################
# Display bucket information
###############################################
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

echo "${BUCKET_NAME}" > s3_bucket_name.txt
log_info "Bucket name saved to s3_bucket_name.txt"
log_info "Script completed successfully"