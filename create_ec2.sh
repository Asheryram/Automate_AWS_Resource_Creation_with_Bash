#!/bin/bash

###############################################
# Script: create_ec2.sh
# Purpose: Automate EC2 instance creation using state manager
###############################################

set -euo pipefail

# ------------------------------------------------
# Paths
# ------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/logger.sh"
source "${SCRIPT_DIR}/lib/args.sh"
source "${SCRIPT_DIR}/lib/checks.sh"
source "${SCRIPT_DIR}/lib/prompts.sh"
source "${SCRIPT_DIR}/lib/output.sh"
source "${SCRIPT_DIR}/lib/state.sh"

# ------------------------------------------------
# Args & Guards (BEFORE state_manager!)
# ------------------------------------------------
parse_dry_run_flag "$@"
check_dependencies "aws" "jq"
check_aws_credentials
check_aws_region "${AWS_REGION:-}"

# Now safe to source state_manager
source "${SCRIPT_DIR}/state/state_manager.sh"

# ------------------------------------------------
# Config
# ------------------------------------------------
INSTANCE_TYPE="${INSTANCE_TYPE:-t3.micro}"
AWS_REGION="${AWS_REGION:-eu-central-1}"
TAG_PROJECT="${TAG_PROJECT:-AutomationLab}"
SG_NAME="${SG_NAME:-devops-sg}"
SSH_CIDR=$(get_cidr_or_env "SSH_CIDR" "SSH")

print_header "EC2 Creation via State Manager"
[[ "$DRY_RUN" == "true" ]] && print_dry_run_notice

# Initialize state (local + remote)
init_state

# ------------------------------------------------
# Dry-run summary
# ------------------------------------------------
if [[ "$DRY_RUN" == "true" ]]; then
  print_dryrun_header
  log_dryrun "The script will perform the following actions:"

  # Step 1: Resolve AMI
  log_dryrun "1️ Resolve AMI:"
  AMI_ID=$(aws ec2 describe-images \
    --region "$AWS_REGION" \
    --owners amazon \
    --filters \
      "Name=name,Values=amzn2-ami-hvm-*-x86_64-gp2" \
      "Name=state,Values=available" \
    --query 'Images | sort_by(@,&CreationDate) | [-1].ImageId' \
    --output text 2>/dev/null || echo "(known after apply)")
  log_dryrun "   AMI ID: $AMI_ID"

  # Step 2: Security groups
  EXISTING_SG_IDS=$(state_list "security_group" 2>/dev/null || true)
  log_dryrun "2️ Security Groups:"
  if [[ -n "$EXISTING_SG_IDS" ]]; then
    for sg in $EXISTING_SG_IDS; do
      SG_NAME=$(jq -r --arg sg "$sg" '.resources.security_group[$sg].name' "$STATE_LOCAL")
      REGION=$(jq -r --arg sg "$sg" '.resources.security_group[$sg].region' "$STATE_LOCAL")
      CREATED=$(jq -r --arg sg "$sg" '.resources.security_group[$sg].created_at' "$STATE_LOCAL")
      log_dryrun "   - $sg | Name: $SG_NAME | Region: $REGION | Created: $CREATED"
    done
  else
    log_dryrun "   New security group will be created: $SG_NAME"
    log_dryrun "   Ingress Rules: SSH (22) from $SSH_CIDR"
  fi

  # Step 3: Key pairs
  EXISTING_KEYPAIRS=$(state_list "keypair" 2>/dev/null || true)
  log_dryrun "3️ Key Pairs:"
  if [[ -n "$EXISTING_KEYPAIRS" ]]; then
    for k in $EXISTING_KEYPAIRS; do
      REGION=$(jq -r --arg k "$k" '.resources.keypair[$k].region' "$STATE_LOCAL")
      CREATED=$(jq -r --arg k "$k" '.resources.keypair[$k].created_at' "$STATE_LOCAL")
      log_dryrun "   - $k.pem | Region: $REGION | Created: $CREATED"
    done
  else
    log_dryrun "   No key pairs yet -> (will be created) (known after apply)"
  fi

  # Step 4: EC2 instances
  EXISTING_INSTANCES=$(state_list "ec2" 2>/dev/null || true)
  log_dryrun "4️ EC2 Instances:"
  log_dryrun "   Region: $AWS_REGION"
  log_dryrun "   Instance Type: $INSTANCE_TYPE"
  log_dryrun "   Tags: Project=$TAG_PROJECT"
  if [[ -n "$EXISTING_INSTANCES" ]]; then
    for i in $EXISTING_INSTANCES; do
      NAME=$(jq -r --arg i "$i" '.resources.ec2[$i].name' "$STATE_LOCAL")
      REGION=$(jq -r --arg i "$i" '.resources.ec2[$i].region' "$STATE_LOCAL")
      TYPE=$(jq -r --arg i "$i" '.resources.ec2[$i].instance_type' "$STATE_LOCAL")
      AMI=$(jq -r --arg i "$i" '.resources.ec2[$i].ami' "$STATE_LOCAL")
      SG=$(jq -r --arg i "$i" '.resources.ec2[$i].security_group' "$STATE_LOCAL")
      KEY=$(jq -r --arg i "$i" '.resources.ec2[$i].keypair' "$STATE_LOCAL")
      CREATED=$(jq -r --arg i "$i" '.resources.ec2[$i].created_at' "$STATE_LOCAL")
      log_dryrun "   - $i | Name: $NAME | Type: $TYPE | AMI: $AMI | SG: $SG | Key: $KEY.pem | Region: $REGION | Created: $CREATED | IPs: (known after apply)"
    done
  else
    log_dryrun "   New instance will be created with above configuration (ID: known after apply)"
  fi

  print_dryrun_footer
  exit 0
fi

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

# Authorize SSH access
log_info "Adding SSH ingress rule to security group..."
aws ec2 authorize-security-group-ingress \
  --group-id "$SG_ID" \
  --protocol tcp \
  --port 22 \
  --cidr "$SSH_CIDR" \
  --region "$AWS_REGION" >/dev/null 2>&1 || log_warn "SSH rule may already exist"
log_info "✓ Security group configured (SSH from $SSH_CIDR)"

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
INSTANCE_ID=$(ec2_create "AutomationLabInstance" "$AMI_ID" "$INSTANCE_TYPE" "$SG_ID" "$KEY_NAME")

log_info "Waiting for instance to be running..."
aws ec2 wait instance-running --region "$AWS_REGION" --instance-ids "$INSTANCE_ID"

# ------------------------------------------------
# Fetch IPs
# ------------------------------------------------
PUBLIC_IP=$(aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
PRIVATE_IP=$(aws ec2 describe-instances \
  --region "$AWS_REGION" \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
[[ "$PUBLIC_IP" == "None" ]] && PUBLIC_IP="N/A"

# ------------------------------------------------
# Output
# ------------------------------------------------
print_footer "EC2 Created & Tracked in State"
log_info "Instance ID: $INSTANCE_ID"
log_info "Public IP: $PUBLIC_IP"
log_info "Private IP: $PRIVATE_IP"
log_info "Key Pair: $KEY_NAME.pem"
log_info "Security Group: $SG_ID"

[[ "$PUBLIC_IP" != "N/A" ]] \
  && log_info "SSH: ssh -i $KEY_NAME.pem ec2-user@$PUBLIC_IP" \
  || log_info "SSH: ssh -i $KEY_NAME.pem ec2-user@$PRIVATE_IP"

print_footer "Setup Complete"
log_info "Script completed successfully"
