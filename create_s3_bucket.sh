#!/bin/bash

###############################################
# Script: create_s3_bucket.sh
# Purpose: Create S3 bucket + track in state
###############################################

set -euo pipefail

# ------------------------------------------------
# Paths
# ------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logger.sh"
source "${SCRIPT_DIR}/state/state_manager.sh"

# ------------------------------------------------
# Args
# ------------------------------------------------
DRY_RUN="${DRY_RUN:-false}"

while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run|--dry)
      DRY_RUN="true"
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--dry-run]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# ------------------------------------------------
# Config
# ------------------------------------------------
REGION="eu-central-1"
SAMPLE_FILE="welcome.txt"
CLEAN_USER=$(whoami | tr -cd '[:alnum:]' | tr '[:upper:]' '[:lower:]')
BUCKET_NAME="automation-lab-bucket-$(date +%s)-${CLEAN_USER}"

log_info "=========================================="
log_info "S3 Bucket Creation via State Manager"
[[ "$DRY_RUN" == "true" ]] && log_warn "DRY-RUN MODE ENABLED"
log_info "=========================================="

# ------------------------------------------------
# Guards
# ------------------------------------------------
command -v aws >/dev/null || { log_error "AWS CLI missing"; exit 1; }
aws sts get-caller-identity >/dev/null || { log_error "AWS credentials missing"; exit 1; }

# ------------------------------------------------
# Dry-run summary
# ------------------------------------------------
if [[ "$DRY_RUN" == "true" ]]; then
  log_dryrun "Planned actions:"
  log_dryrun "1. Create S3 bucket: ${BUCKET_NAME}"
  log_dryrun "2. Enable versioning"
  log_dryrun "3. Add tags (Project, Environment)"
  log_dryrun "4. Upload sample file"
  log_dryrun "5. Track bucket in remote state"
  exit 0
fi

# ------------------------------------------------
# State init
# ------------------------------------------------
state_init

# ------------------------------------------------
# Step 1: Create bucket
# ------------------------------------------------
log_info "[1/5] Creating S3 bucket: ${BUCKET_NAME}"

if [[ "$REGION" == "us-east-1" ]]; then
  aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$REGION"
else
  aws s3api create-bucket \
    --bucket "$BUCKET_NAME" \
    --region "$REGION" \
    --create-bucket-configuration LocationConstraint="$REGION"
fi

log_info "✓ Bucket created"

# ------------------------------------------------
# Step 2: Enable versioning
# ------------------------------------------------
log_info "[2/5] Enabling versioning"

aws s3api put-bucket-versioning \
  --bucket "$BUCKET_NAME" \
  --versioning-configuration Status=Enabled

log_info "✓ Versioning enabled"

# ------------------------------------------------
# Step 3: Add tags
# ------------------------------------------------
log_info "[3/5] Adding tags"

aws s3api put-bucket-tagging \
  --bucket "$BUCKET_NAME" \
  --tagging 'TagSet=[{Key=Project,Value=AutomationLab},{Key=Environment,Value=Development}]' \
  || log_warn "Tagging failed (non-critical)"

# ------------------------------------------------
# Step 4: Upload sample file
# ------------------------------------------------
log_info "[4/5] Creating and uploading sample file"

cat > "$SAMPLE_FILE" <<EOF
Welcome to the Automation Lab!
Created: $(date)
Bucket: $BUCKET_NAME
Region: $REGION
User: $CLEAN_USER
EOF

aws s3 cp "$SAMPLE_FILE" "s3://${BUCKET_NAME}/${SAMPLE_FILE}"

log_info "✓ Sample file uploaded"

# ------------------------------------------------
# Step 5: Track bucket in state
# ------------------------------------------------
log_info "[5/5] Tracking bucket in remote state"
s3_track "$BUCKET_NAME"

# ------------------------------------------------
# Output
# ------------------------------------------------
log_info "=========================================="
log_info "S3 Bucket Created & Tracked"
log_info "Bucket: $BUCKET_NAME"
log_info "Region: $REGION"
log_info "Versioning: Enabled"
log_info "=========================================="

echo "$BUCKET_NAME" > s3_bucket_name.txt
log_info "Bucket name saved to s3_bucket_name.txt"
log_info "Script completed successfully"
