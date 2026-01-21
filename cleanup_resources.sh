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

# Function to confirm deletion
confirm_deletion() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Skipping confirmation prompt"
        return 0
    fi
    
    read -rp "Do you want to proceed with cleanup? (yes/no) " response
    [[ "$response" == "yes" ]] || { log_info "Cleanup cancelled by user"; exit 0; }
    log_info "Cleanup confirmed, proceeding..."
}
confirm_deletion

###############################################
# Step 1: Terminate EC2 Instances
###############################################
log_info "[1/4] Searching for EC2 instances with tag Project=AutomationLab"

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would query for instances with filters:"
    log_info "[DRY-RUN]   Tag: Project=AutomationLab"
    log_info "[DRY-RUN]   State: running,stopped,pending"
    INSTANCES="i-example1 i-example2"  # Example instances
    log_info "[DRY-RUN] Would find instances: ${INSTANCES}"
else
    INSTANCES=$(aws ec2 describe-instances \
        --filters "Name=tag:Project,Values=AutomationLab" "Name=instance-state-name,Values=running,stopped,pending" \
        --query 'Reservations[*].Instances[*].InstanceId' \
        --output text 2>/dev/null)
fi

# Guard: Check if instances exist
[[ -n "$INSTANCES" ]] || log_info "No instances found to terminate"

if [ -n "$INSTANCES" ]; then
    log_info "Found instances: $INSTANCES"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would terminate instances: ${INSTANCES}"
        log_info "[DRY-RUN] Would wait for instances to terminate"
    else
        log_info "Terminating instances..."
        aws ec2 terminate-instances --instance-ids $INSTANCES >/dev/null 2>&1 || log_error "Failed to terminate instances"
        
        log_info "Waiting for instances to terminate..."
        aws ec2 wait instance-terminated --instance-ids $INSTANCES 2>/dev/null || log_warn "Instance termination wait timed out or failed"
    fi
    
    log_info "✓ All instances terminated successfully"
fi

###############################################
# Step 2: Delete Key Pairs
###############################################
log_info "[2/4] Searching for automation lab key pairs"

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would query for key pairs matching: automation-lab-key-*"
    KEY_PAIRS="automation-lab-key-example1 automation-lab-key-example2"
    log_info "[DRY-RUN] Would find key pairs: ${KEY_PAIRS}"
else
    KEY_PAIRS=$(aws ec2 describe-key-pairs \
        --filters "Name=key-name,Values=automation-lab-key-*" \
        --query 'KeyPairs[*].KeyName' \
        --output text 2>/dev/null)
fi

# Guard: Check if key pairs exist
[[ -n "$KEY_PAIRS" ]] || log_info "No key pairs found"

for key in $KEY_PAIRS; do
    log_info "Deleting key pair: $key"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would delete key pair: ${key}"
        log_info "[DRY-RUN] Would delete local file: ${key}.pem (if exists)"
    else
        aws ec2 delete-key-pair --key-name "$key" 2>/dev/null || log_warn "Failed to delete key pair: $key"
        
        if [[ -f "${key}.pem" ]]; then
            rm "${key}.pem"
            log_info "  ✓ Deleted local file: ${key}.pem"
        fi
    fi
done

###############################################
# Step 3: Delete Security Groups (retry)
###############################################
log_info "[3/4] Searching for security group: devops-sg"

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would query for security group: devops-sg"
    SG_ID="sg-dry-run-example"
    log_info "[DRY-RUN] Would find security group: ${SG_ID}"
else
    SG_ID=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=devops-sg" \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null || echo "None")
fi

# Guard: Check if security group exists
[[ "$SG_ID" != "None" ]] || log_info "No security group found"

if [ "$SG_ID" != "None" ]; then
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would attempt to delete security group: ${SG_ID}"
        log_info "[DRY-RUN] Would retry up to 5 times if in use"
    else
        # Retry deletion a few times if in use
        MAX_RETRIES=5
        for i in $(seq 1 $MAX_RETRIES); do
            aws ec2 delete-security-group --group-id "$SG_ID" 2>/dev/null && break
            log_warn "Attempt $i: Security group still in use. Retrying in 5s..."
            sleep 5
        done

        # Final check
        aws ec2 describe-security-groups --group-ids "$SG_ID" >/dev/null 2>&1 && log_warn "Failed to delete security group (may still be in use)"
    fi
    
    log_info "✓ Security group deletion attempted"
fi

###############################################
# Step 4: Delete S3 Buckets (handles versions, delete markers, multipart uploads)
###############################################
log_info "[4/4] Searching for automation lab S3 buckets"

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would query for buckets matching: automation-lab-bucket-*"
    BUCKETS="automation-lab-bucket-example1 automation-lab-bucket-example2"
    log_info "[DRY-RUN] Would find buckets: ${BUCKETS}"
else
    BUCKETS=$(aws s3api list-buckets \
        --query 'Buckets[?starts_with(Name, `automation-lab-bucket-`)].Name' \
        --output text 2>/dev/null)
fi

# Guard: Check if buckets exist
[[ -n "$BUCKETS" ]] || log_info "No S3 buckets found"

for bucket in $BUCKETS; do
    log_info "Processing bucket: $bucket"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would empty bucket: ${bucket}"
        log_info "[DRY-RUN] Would delete all object versions"
        log_info "[DRY-RUN] Would delete all delete markers"
        log_info "[DRY-RUN] Would abort all multipart uploads"
        log_info "[DRY-RUN] Would delete bucket: ${bucket}"
        continue
    fi

    # Empty all objects
    aws s3 rm "s3://${bucket}" --recursive >/dev/null 2>&1 && log_info "  ✓ Bucket emptied" || log_warn "  Failed to empty bucket"

    # Delete object versions
    VERSIONS=$(aws s3api list-object-versions --bucket "$bucket" \
        --query 'Versions[].{Key:Key,VersionId:VersionId}' --output text 2>/dev/null)
    if [ -n "$VERSIONS" ]; then
        log_info "  Deleting versioned objects..."
        while read -r key version; do
            # Guard: Skip if key or version is empty
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
            # Guard: Skip if key or version is empty
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
            # Guard: Skip if upload ID is empty
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

if [[ "$DRY_RUN" == "true" ]]; then
    log_info "[DRY-RUN] Would delete local files:"
    log_info "[DRY-RUN]   - ec2_instance_info.txt"
    log_info "[DRY-RUN]   - security_group_id.txt"
    log_info "[DRY-RUN]   - s3_bucket_name.txt"
    log_info "[DRY-RUN]   - welcome.txt"
else
    rm -f ec2_instance_info.txt security_group_id.txt s3_bucket_name.txt welcome.txt
    log_info "✓ Local files cleaned up"
fi

log_info ""
log_info "=========================================="
log_info "Cleanup Complete!"
log_info "=========================================="
log_info "Check the log file for details: ${LOG_FILE}"