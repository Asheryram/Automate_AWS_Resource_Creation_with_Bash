#!/usr/bin/env bash
set -euo pipefail

###############################################
# Script: cleanup_resources.sh
# Purpose: Clean up AWS resources tracked in remote S3 state.json
# Author: [Your Name]
###############################################

# =========================
# Source dependencies
# =========================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logger.sh"
source "${SCRIPT_DIR}/state/state_manager.sh"

DRY_RUN="${DRY_RUN:-false}"

# =========================
# Parse CLI arguments
# =========================
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
            exit 1
            ;;
    esac
done

log_info "=========================================="
log_info "AWS Resources Cleanup Script Started"
[[ "$DRY_RUN" == "true" ]] && log_dryrun "DRY-RUN MODE: No changes will be made"
log_info "=========================================="

# =========================
# Ensure AWS CLI and jq
# =========================
command -v aws >/dev/null || { log_error "AWS CLI required"; exit 1; }
command -v jq >/dev/null || { log_error "jq required"; exit 1; }

# =========================
# Pull state from S3 (state_manager handles creation)
# =========================
state_init
state_pull

STATE_FILE="$STATE_LOCAL"  # state_manager.sh manages the local copy

# =========================
# Load resources safely
# =========================
EC2_IDS=$(jq -r '.resources.ec2 // {} | keys[]' "$STATE_FILE")
KEYPAIR_NAMES=$(jq -r '.resources.keypair // {} | keys[]' "$STATE_FILE")
SG_IDS=$(jq -r '.resources.security_group // {} | keys[]' "$STATE_FILE")
S3_BUCKETS=$(jq -r '.resources.s3 // {} | keys[]' "$STATE_FILE")

# =========================
# Dry-run summary
# =========================
if [[ "$DRY_RUN" == "true" ]]; then
    log_dryrun ""
    log_dryrun "=========================================="
    log_dryrun "DRY-RUN SUMMARY"
    log_dryrun "=========================================="

    log_dryrun "Resources tracked in remote state.json that would be deleted:"

    log_dryrun "EC2 Instances:"
    [[ -n "$EC2_IDS" ]] && for id in $EC2_IDS; do log_dryrun "  - $id"; done || log_dryrun "  None"

    log_dryrun "Key Pairs:"
    [[ -n "$KEYPAIR_NAMES" ]] && for k in $KEYPAIR_NAMES; do log_dryrun "  - $k"; done || log_dryrun "  None"

    log_dryrun "Security Groups:"
    [[ -n "$SG_IDS" ]] && for sg in $SG_IDS; do log_dryrun "  - $sg"; done || log_dryrun "  None"

    log_dryrun "S3 Buckets:"
    [[ -n "$S3_BUCKETS" ]] && for b in $S3_BUCKETS; do log_dryrun "  - $b"; done || log_dryrun "  None"

    log_dryrun "=========================================="
    log_dryrun "No resources will be deleted in dry-run mode"
    exit 0
fi

# =========================
# Confirm deletion
# =========================
log_info ""
log_info "=========================================="
log_info "RESOURCES TO BE DELETED"
log_info "=========================================="

log_info "EC2 Instances:"
if [[ -n "$EC2_IDS" ]]; then
  for id in $EC2_IDS; do
    NAME=$(jq -r --arg id "$id" '.resources.ec2[$id].name // "N/A"' "$STATE_FILE")
    TYPE=$(jq -r --arg id "$id" '.resources.ec2[$id].instance_type // "N/A"' "$STATE_FILE")
    AMI=$(jq -r --arg id "$id" '.resources.ec2[$id].ami // "N/A"' "$STATE_FILE")
    CREATED=$(jq -r --arg id "$id" '.resources.ec2[$id].created_at // "N/A"' "$STATE_FILE")
    log_info "  - $id | Name: $NAME | Type: $TYPE | AMI: $AMI | Created: $CREATED"
  done
else
  log_info "  None"
fi

log_info "Key Pairs:"
if [[ -n "$KEYPAIR_NAMES" ]]; then
  for k in $KEYPAIR_NAMES; do
    CREATED=$(jq -r --arg k "$k" '.resources.keypair[$k].created_at // "N/A"' "$STATE_FILE")
    log_info "  - $k | Created: $CREATED"
  done
else
  log_info "  None"
fi

log_info "Security Groups:"
if [[ -n "$SG_IDS" ]]; then
  for sg in $SG_IDS; do
    NAME=$(jq -r --arg sg "$sg" '.resources.security_group[$sg].name // "N/A"' "$STATE_FILE")
    CREATED=$(jq -r --arg sg "$sg" '.resources.security_group[$sg].created_at // "N/A"' "$STATE_FILE")
    log_info "  - $sg | Name: $NAME | Created: $CREATED"
  done
else
  log_info "  None"
fi

log_info "S3 Buckets:"
if [[ -n "$S3_BUCKETS" ]]; then
  for b in $S3_BUCKETS; do
    CREATED=$(jq -r --arg b "$b" '.resources.s3[$b].created_at // "N/A"' "$STATE_FILE")
    log_info "  - $b | Created: $CREATED"
  done
else
  log_info "  None"
fi

log_info "=========================================="
log_info ""
read -rp "Proceed with deleting all tracked resources? (yes/no) " CONFIRM
[[ "$CONFIRM" == "yes" ]] || { log_info "Cleanup cancelled"; exit 0; }
log_info "Cleanup confirmed. Proceeding..."

# =========================
# Delete EC2 instances
# =========================
for id in $EC2_IDS; do
    log_warn "Terminating EC2: $id"
    if aws ec2 terminate-instances --instance-ids "$id" >/dev/null 2>&1; then
      ec2_delete "$id"
      log_info "✓ EC2 terminated: $id"
    else
      log_error "Failed to terminate EC2: $id"
    fi
done

# Wait for instances to fully terminate before deleting security groups
if [[ -n "$EC2_IDS" ]]; then
  log_info "Waiting for instances to fully terminate..."
  aws ec2 wait instance-terminated --instance-ids $EC2_IDS --region "$AWS_REGION" 2>/dev/null || true
  log_info "✓ All instances terminated"
fi

# =========================
# Delete Key Pairs
# =========================
for k in $KEYPAIR_NAMES; do
    log_warn "Deleting Key Pair: $k"
    if aws ec2 delete-key-pair --key-name "$k" >/dev/null 2>&1; then
      keypair_delete "$k"
      log_info "✓ Key pair deleted: $k"
    else
      log_error "Failed to delete key pair: $k"
    fi
done

# =========================
# Delete Security Groups
# =========================
for sg in $SG_IDS; do
    log_warn "Deleting Security Group: $sg"
    SG_DELETE_OUTPUT=$(aws ec2 delete-security-group --group-id "$sg" 2>&1 || true)
    
    # Check if deletion succeeded or if group doesn't exist (already deleted)
    if echo "$SG_DELETE_OUTPUT" | grep -q "InvalidGroup.NotFound\|InvalidGroupId.NotFound" 2>/dev/null; then
      log_warn "Security group already deleted (not found in AWS)"
      sg_delete "$sg" 2>/dev/null || true
      log_info "✓ Security group removed from state: $sg"
    elif [[ -z "$SG_DELETE_OUTPUT" ]] || echo "$SG_DELETE_OUTPUT" | grep -q "Return\|GroupId" 2>/dev/null; then
      sg_delete "$sg" 2>/dev/null || true
      log_info "✓ Security group deleted: $sg"
    else
      log_error "Failed to delete security group: $sg (may have dependencies)"
    fi
done

# =========================
# Delete S3 Buckets
# =========================
for b in $S3_BUCKETS; do
    log_warn "Deleting S3 Bucket: $b"
    
    # Delete all object versions (for versioned buckets)
    if aws s3api list-object-versions --bucket "$b" >/dev/null 2>&1; then
      aws s3api delete-objects --bucket "$b" \
        --delete "$(aws s3api list-object-versions --bucket "$b" \
          --query 'Versions[].{Key:Key,VersionId:VersionId}' \
          --output json | jq -r '.[] | {Key:.Key,VersionId:.VersionId}' | jq -s '{"Objects":[.[]]}' \
        )" >/dev/null 2>&1 || true
    fi
    
    # Delete all delete markers for versioned buckets
    if aws s3api list-object-versions --bucket "$b" --query 'DeleteMarkers' >/dev/null 2>&1; then
      aws s3api delete-objects --bucket "$b" \
        --delete "$(aws s3api list-object-versions --bucket "$b" \
          --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' \
          --output json | jq -s '{"Objects":[.[]]}' \
        )" >/dev/null 2>&1 || true
    fi
    
    # Delete the bucket
    if aws s3api delete-bucket --bucket "$b" >/dev/null 2>&1; then
      log_info "✓ Bucket deleted: $b"
      s3_untrack "$b"
    else
      log_error "Failed to delete bucket: $b (may have remaining objects or permissions issue)"
    fi
done

log_info "=========================================="
log_info "Cleanup Complete!"
log_info "=========================================="
