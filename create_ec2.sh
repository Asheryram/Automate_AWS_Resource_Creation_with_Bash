#!/bin/bash

###############################################
# Script: create_ec2_dynamic.sh
# Purpose: Automate EC2 instance creation using state manager
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
INSTANCE_TYPE="${INSTANCE_TYPE:-t2.micro}"
AWS_REGION="${AWS_REGION:-eu-central-1}"
TAG_PROJECT="${TAG_PROJECT:-AutomationLab}"
SG_NAME="${SG_NAME:-devops-sg}"

log_info "=========================================="
log_info "EC2 Creation via State Manager"
[[ "$DRY_RUN" == "true" ]] && log_warn "DRY-RUN MODE ENABLED"
log_info "=========================================="

# ------------------------------------------------
# Guards
# ------------------------------------------------
command -v aws >/dev/null || { log_error "AWS CLI missing"; exit 1; }
command -v jq  >/dev/null || { log_error "jq missing"; exit 1; }
aws sts get-caller-identity >/dev/null || { log_error "AWS credentials missing"; exit 1; }

# ------------------------------------------------
# Dry-run summary
# ------------------------------------------------
if [[ "$DRY_RUN" == "true" ]]; then
  log_dryrun "Planned actions:"
  log_dryrun "1. Initialize remote state (S3)"
  log_dryrun "2. Resolve latest Amazon Linux 2 AMI"
  log_dryrun "3. Create security group: ${SG_NAME}"
  log_dryrun "4. Create key pair"
  log_dryrun "5. Launch EC2 instance"
  log_dryrun "6. Persist all resource IDs in remote state"
  exit 0
fi

# ------------------------------------------------
# State init
# ------------------------------------------------
state_init

# ------------------------------------------------
# Step 1: Resolve AMI dynamically
# ------------------------------------------------
log_info "[1/4] Resolving latest Amazon Linux 2 AMI..."

AMI_ID=$(aws ec2 describe-images \
  --region "$AWS_REGION" \
  --owners amazon \
  --filters \
    "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
    "Name=state,Values=available" \
  --query 'Images | sort_by(@,&CreationDate) | [-1].ImageId' \
  --output text)

[[ -n "$AMI_ID" ]] || { log_error "AMI lookup failed"; exit 1; }
log_info "✓ AMI resolved: $AMI_ID"

# ------------------------------------------------
# Step 2: Security group (state-managed)
# ------------------------------------------------
log_info "[2/4] Creating security group via state manager..."
SG_ID=$(sg_create "$SG_NAME")

# ------------------------------------------------
# Step 3: Key pair (state-managed)
# ------------------------------------------------
KEY_NAME="automation-lab-key-$(date +%s)"
log_info "[3/4] Creating key pair via state manager..."
keypair_create "$KEY_NAME"

# ------------------------------------------------
# Step 4: EC2 instance (state-managed)
# ------------------------------------------------
log_info "[4/4] Launching EC2 via state manager..."
INSTANCE_ID=$(ec2_create \
  "AutomationLabInstance" \
  "$AMI_ID" \
  "$INSTANCE_TYPE" \
  "$SG_ID" \
  "$KEY_NAME"
)

log_info "Waiting for instance to be running..."
aws ec2 wait instance-running \
  --region "$AWS_REGION" \
  --instance-ids "$INSTANCE_ID"

# ------------------------------------------------
# Fetch IPs
# ------------------------------------------------
PUBLIC_IP=$(aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

PRIVATE_IP=$(aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' \
  --output text)

[[ "$PUBLIC_IP" == "None" ]] && PUBLIC_IP="N/A"

# ------------------------------------------------
# Output
# ------------------------------------------------
log_info "=========================================="
log_info "EC2 Created & Tracked in State"
log_info "Instance ID: $INSTANCE_ID"
log_info "Public IP: $PUBLIC_IP"
log_info "Private IP: $PRIVATE_IP"
log_info "Key Pair: $KEY_NAME.pem"
log_info "Security Group: $SG_ID"

[[ "$PUBLIC_IP" != "N/A" ]] \
  && log_info "SSH: ssh -i $KEY_NAME.pem ec2-user@$PUBLIC_IP" \
  || log_info "SSH: ssh -i $KEY_NAME.pem ec2-user@$PRIVATE_IP"

log_info "=========================================="
log_info "Script completed successfully"
