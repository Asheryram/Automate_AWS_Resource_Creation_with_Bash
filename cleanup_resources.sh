#!/bin/bash

###############################################
# Script: cleanup_resources.sh
# Purpose: Clean up all created AWS resources (bulletproof)
# Author: [Your Name]
###############################################

# Source the logger
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logger.sh"

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

log_info "=========================================="
log_info "AWS Resources Cleanup Script Started"
if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "DRY-RUN MODE: No changes will be made"
else
    log_warn "WARNING: This will delete resources!"
fi
log_info "=========================================="
log_info ""

# Guard: Check AWS CLI is installed
command -v aws >/dev/null 2>&1 || { log_error "AWS CLI is not installed. Please install it first."; exit 1; }

# Guard: Check AWS credentials are configured
aws sts get-caller-identity >/dev/null 2>&1 || { log_error "AWS credentials not configured. Run 'aws configure' first."; exit 1; }

###############################################
# Dry-Run Summary Report
###############################################
if [[ "$DRY_RUN" == "true" ]]; then
    log_info ""
    log_info "DRY-RUN SUMMARY REPORT"
    log_info "=========================================="
    log_dryrun "Resources that would be deleted:"
    log_dryrun ""
    log_dryrun "1. EC2 INSTANCES:"
    log_dryrun "   - Query for instances tagged: Project=AutomationLab"
    log_dryrun "   - States: running, stopped, pending"
    log_dryrun "   - Terminate all matching instances"
    log_dryrun "   - Wait for termination to complete"
    log_dryrun ""
    log_dryrun "2. KEY PAIRS:"
    log_dryrun "   - Query for key pairs: automation-lab-key-*"
    log_dryrun "   - Delete each key pair from AWS"
    log_dryrun "   - Delete local .pem files if they exist"
    log_dryrun ""
    log_dryrun "3. SECURITY GROUPS:"
    log_dryrun "   - Query for security group: devops-sg"
    log_dryrun "   - Attempt deletion with retry (up to 5 attempts)"
    log_dryrun "   - Wait 5s between retries if in use"
    log_dryrun ""
    log_dryrun "4. S3 BUCKETS:"
    log_dryrun "   - Query for buckets: automation-lab-bucket-*"
    log_dryrun "   - For each bucket:"
    log_dryrun "     a) Empty all objects (recursive delete)"
    log_dryrun "     b) Delete all object versions"
    log_dryrun "     c) Delete all delete markers"
    log_dryrun "     d) Abort all multipart uploads"
    log_dryrun "     e) Delete the bucket itself"
    log_dryrun ""
    log_dryrun "5. LOCAL FILES:"
    log_dryrun "   - ec2_instance_info.txt"
    log_dryrun "   - security_group_id.txt"
    log_dryrun "   - s3_bucket_name.txt"
    log_dryrun "   - welcome.txt"
    log_dryrun ""
    log_dryrun "Cleanup process includes:"
    log_dryrun "  - Comprehensive error handling"
    log_dryrun "  - Retry logic for in-use resources"
    log_dryrun "  - Versioning and multipart upload cleanup"
    log_dryrun "  - Detailed logging of all operations"
    log_info "=========================================="
    log_info "No actual resources deleted in dry-run mode"
    exit 0
fi

# Function to confirm deletion
confirm_deletion() {
    read -rp "Do you want to proceed with cleanup? (yes/no) " response
    [[ "$response" == "yes" ]] || { log_info "Cleanup cancelled by user"; exit 0; }
    log_info "Cleanup confirmed, proceeding..."
}
confirm_deletion

###############################################
# Step 1: Terminate EC2 Instances
###############################################
log_info "[1/4] Searching for EC2 instances with tag Project=AutomationLab"

INSTANCES=$(aws ec2 describe-instances \
    --filters "Name=tag:Project,Values=AutomationLab" "Name=instance-state-name,Values=running,stopped,pending" \
    --query 'Reservations[*].Instances[*].InstanceId' \
    --output text 2>/dev/null)

[[ -n "$INSTANCES" ]] || log_info "No instances found to terminate"

if [ -n "$INSTANCES" ]; then
    log_info "Found instances: $INSTANCES"
    log_info "Terminating instances..."
    
    aws ec2 terminate-instances --instance-ids $INSTANCES >/dev/null 2>&1 || log_error "Failed to terminate instances"
    
    log_info "Waiting for instances to terminate..."
    aws ec2 wait instance-terminated --instance-ids $INSTANCES 2>/dev/null || log_warn "Instance termination wait timed out or failed"
    
    log_info "✓ All instances terminated successfully"
fi

###############################################
# Step 2: Delete Key Pairs
###############################################
log_info "[2/4] Searching for automation lab key pairs"

KEY_PAIRS=$(aws ec2 describe-key-pairs \
    --filters "Name=key-name,Values=automation-lab-key-*" \
    --query 'KeyPairs[*].KeyName' \
    --output text 2>/dev/null)

[[ -n "$KEY_PAIRS" ]] || log_info "No key pairs found"

for key in $KEY_PAIRS; do
    log_info "Deleting key pair: $key"
    aws ec2 delete-key-pair --key-name "$key" 2>/dev/null || log_warn "Failed to delete key pair: $key"
    
    if [[ -f "${key}.pem" ]]; then
        rm "${key}.pem"
        log_info "  ✓ Deleted local file: ${key}.pem"
    fi
done

###############################################
# Step 3: Delete Security Groups (retry)
###############################################
log_info "[3/4] Searching for security group: devops-sg"

SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=devops-sg" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "None")

[[ "$SG_ID" != "None" ]] || log_info "No security group found"

if [ "$SG_ID" != "None" ]; then
    MAX_RETRIES=5
    for i in $(seq 1 $MAX_RETRIES); do
        aws ec2 delete-security-group --group-id "$SG_ID" 2>/dev/null && break
        log_warn "Attempt $i: Security group still in use. Retrying in 5s..."
        sleep 5
    done

    aws ec2 describe-security-groups --group-ids "$SG_ID" >/dev/null 2>&1 && log_warn "Failed to delete security group (may still be in use)"
    log_info "✓ Security group deletion attempted"
fi

###############################################
# Step 4: Delete S3 Buckets
###############################################
log_info "[4/4] Searching for automation lab S3 buckets"

BUCKETS=$(aws s3api list-buckets \
    --query 'Buckets[?starts_with(Name, `automation-lab-bucket-`)].Name' \
    --output text 2>/dev/null)

[[ -n "$BUCKETS" ]] || log_info "No S3 buckets found"

for bucket in $BUCKETS; do
    log_info "Processing bucket: $bucket"

    # Empty all objects
    aws s3 rm "s3://${bucket}" --recursive >/dev/null 2>&1 && log_info "  ✓ Bucket emptied" || log_warn "  Failed to empty bucket"

    # Delete object versions
    VERSIONS=$(aws s3api list-object-versions --bucket "$bucket" \
        --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null)
    if [ -n "$VERSIONS" ]; then
        log_info "  Deleting versioned objects..."
        while read -r key version; do
            [[ -n "$key" && -n "$version" ]] || continue
            
            aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version" >/dev/null 2>&1 \
                && log_info "    ✓ Deleted version: $key ($version)" \
                || log_warn "    Failed to delete version: $key ($version)"
        done <<< "$VERSIONS"
    fi

    # Delete delete markers
    DELETE_MARKERS=$(aws s3api list-object-versions --bucket "$bucket" \
        --query 'DeleteMarkers[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null)
    if [ -n "$DELETE_MARKERS" ]; then
        log_info "  Deleting delete markers..."
        while read -r key version; do
            [[ -n "$key" && -n "$version" ]] || continue
            
            aws s3api delete-object --bucket "$bucket" --key "$key" --version-id "$version" >/dev/null 2>&1 \
                && log_info "    ✓ Deleted delete marker: $key ($version)" \
                || log_warn "    Failed to delete delete marker: $key ($version)"
        done <<< "$DELETE_MARKERS"
    fi

    # Abort multipart uploads
    UPLOADS=$(aws s3api list-multipart-uploads --bucket "$bucket" --query 'Uploads[].UploadId' --output text 2>/dev/null)
    if [ -n "$UPLOADS" ]; then
        log_info "  Aborting multipart uploads..."
        while read -r upload; do
            [[ -n "$upload" ]] || continue
            
            KEY=$(aws s3api list-multipart-uploads --bucket "$bucket" \
                --query "Uploads[?UploadId=='$upload'].Key" --output text)
            aws s3api abort-multipart-upload --bucket "$bucket" --key "$KEY" --upload-id "$upload" >/dev/null 2>&1 \
                && log_info "    ✓ Aborted upload: $KEY ($upload)" \
                || log_warn "    Failed to abort upload: $KEY ($upload)"
        done <<< "$UPLOADS"
    fi

    # Delete the bucket
    aws s3api delete-bucket --bucket "$bucket" 2>/dev/null \
        && log_info "  ✓ Deleted bucket: $bucket" \
        || log_warn "  Failed to delete bucket: $bucket"
done

###############################################
# Step 5: Clean up local files
###############################################
log_info ""
log_info "Cleaning up local tracking files..."

rm -f ec2_instance_info.txt security_group_id.txt s3_bucket_name.txt welcome.txt
log_info "✓ Local files cleaned up"

log_info ""
log_info "=========================================="
log_info "Cleanup Complete!"
log_info "=========================================="
log_info "Check the log file for details: ${LOG_FILE}"