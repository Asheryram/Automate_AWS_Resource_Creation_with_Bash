#!/usr/bin/env bash
set -euo pipefail

###############################################
# Script: cleanup_resources.sh
# Purpose: Clean up all AWS resources tracked in state.json
# Author: [Your Name]
###############################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logger.sh"
source "${SCRIPT_DIR}/state_manager.sh"

# Parse command-line arguments
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

log_info "=========================================="
log_info "AWS Resources Cleanup Script Started"
[[ "$DRY_RUN" == "true" ]] && log_warn "DRY-RUN MODE: No changes will be made"
log_info "=========================================="

# Initialize state backend
state_init
state_pull

# Dry-run summary
if [[ "$DRY_RUN" == "true" ]]; then
    log_info ""
    log_info "DRY-RUN SUMMARY"
    log_info "=========================================="
    log_info "Resources tracked in state.json that would be deleted:"
    log_info "EC2 Instances: $(state_list ec2 | tr '\n' ' ')"
    log_info "Key Pairs: $(state_list keypair | tr '\n' ' ')"
    log_info "Security Groups: $(state_list security_group | tr '\n' ' ')"
    log_info "S3 Buckets: $(state_list s3 | tr '\n' ' ')"
    log_info "=========================================="
    exit 0
fi

# Confirm deletion
read -rp "Do you want to proceed with cleanup? (yes/no) " response
[[ "$response" == "yes" ]] || { log_info "Cleanup cancelled by user"; exit 0; }
log_info "Cleanup confirmed, proceeding..."

###############################################
# Step 1: Delete EC2 instances
###############################################
for instance_id in $(state_list ec2); do
    log_info "Terminating EC2 instance: $instance_id"
    ec2_delete "$instance_id"
done

###############################################
# Step 2: Delete Key Pairs
###############################################
for key_name in $(state_list keypair); do
    log_info "Deleting keypair: $key_name"
    keypair_delete "$key_name"
done

###############################################
# Step 3: Delete Security Groups
###############################################
for sg_id in $(state_list security_group); do
    log_info "Deleting security group: $sg_id"
    MAX_RETRIES=5
    for i in $(seq 1 $MAX_RETRIES); do
        if sg_delete "$sg_id" 2>/dev/null; then
            log_info "✓ Deleted SG $sg_id"
            break
        else
            log_warn "Attempt $i: Security group $sg_id still in use, retrying in 5s..."
            sleep 5
        fi
    done
done

###############################################
# Step 4: Delete S3 Buckets
###############################################
for bucket in $(state_list s3); do
    log_info "Deleting S3 bucket: $bucket"
    
    # Empty bucket (objects + versions + delete markers)
    aws s3 rm "s3://$bucket" --recursive >/dev/null 2>&1 || log_warn "Failed to empty bucket $bucket"

    VERSIONS=$(aws s3api list-object-versions --bucket "$bucket" --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null)
    if [ -n "$VERSIONS" ]; then
        while read -r key version; do
            [[ -n "$key" && -n "$version" ]] || continue
            aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version" >/dev/null 2>&1
        done <<< "$VERSIONS"
    fi

    DELETE_MARKERS=$(aws s3api list-object-versions --bucket "$bucket" --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null)
    if [ -n "$DELETE_MARKERS" ]; then
        while read -r key version; do
            [[ -n "$key" && -n "$version" ]] || continue
            aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version" >/dev/null 2>&1
        done <<< "$DELETE_MARKERS"
    fi

    # Abort multipart uploads
    UPLOADS=$(aws s3api list-multipart-uploads --bucket "$bucket" --query 'Uploads[].UploadId' --output text 2>/dev/null)
    if [ -n "$UPLOADS" ]; then
        while read -r upload; do
            KEY=$(aws s3api list-multipart-uploads --bucket "$bucket" --query "Uploads[?UploadId=='$upload'].Key" --output text)
            aws s3api abort-multipart-upload --bucket "$bucket" --key "$KEY" --upload-id "$upload" >/dev/null 2>&1
        done <<< "$UPLOADS"
    fi

    # Delete the bucket itself
    aws s3api delete-bucket --bucket "$bucket" >/dev/null 2>&1 || log_warn "Failed to delete bucket $bucket"

    # Remove from state
    s3_untrack "$bucket"
done

###############################################
# Step 5: Cleanup local files
###############################################
log_info "Cleaning up local tracking files..."
rm -f ec2_instance_info.txt security_group_id.txt s3_bucket_name.txt welcome.txt
log_info "✓ Local files cleaned up"

log_info ""
log_info "=========================================="
log_info "Cleanup Complete! All resources removed from AWS and state."
log_info "=========================================="
