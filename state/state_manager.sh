#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Source logger
# ============================================================
source "$(dirname "${BASH_SOURCE[0]}")/../logger.sh"

# ============================================================
# Configuration
# ============================================================
AWS_REGION="${AWS_REGION:-eu-central-1}"
STATE_KEY="${STATE_KEY:-state.json}"
STATE_LOCAL="./$STATE_KEY"

# State bucket name file - persists the bucket name across runs
STATE_BUCKET_FILE="$(dirname "${BASH_SOURCE[0]}")/../.state_bucket_name"

# Resolve STATE_BUCKET: check file first, then create new with date
_resolve_state_bucket() {
  # If already set via environment, use that
  if [[ -n "${STATE_BUCKET:-}" ]]; then
    log_info "Using existing state bucket from environment: $STATE_BUCKET"
    return
  fi
  
  # Check if we have a saved bucket name
  if [[ -f "$STATE_BUCKET_FILE" ]]; then
    local saved_bucket
    saved_bucket=$(cat "$STATE_BUCKET_FILE" | tr -d '[:space:]')
    if [[ -n "$saved_bucket" ]]; then
      log_info "Using existing state bucket from file: $saved_bucket"
      return
    fi
  fi
  
  # Generate new bucket name with date (YYYYMMDD format for readability)
  local new_bucket="aws-project-state-$(date +%Y%m%d)-$$"
  echo "$new_bucket" > "$STATE_BUCKET_FILE"
  log_info "Created new state bucket: $new_bucket"
}

STATE_BUCKET="$(_resolve_state_bucket)"

LOG_LEVEL="${LOG_LEVEL:-INFO}"
CONSOLE_LOG="${CONSOLE_LOG:-true}"

# ============================================================
# Requirements
# ============================================================
command -v aws >/dev/null || { log_error "AWS CLI required"; exit 1; }
command -v jq >/dev/null || { log_error "jq required"; exit 1; }

# ============================================================
# State Backend
# ============================================================
ensure_bucket_exists() {
  if ! aws s3api head-bucket --bucket "$STATE_BUCKET" >/dev/null 2>&1; then
    log_warn "State bucket '$STATE_BUCKET' does not exist. Creating it..."
    aws s3 mb "s3://$STATE_BUCKET" --region "$AWS_REGION" >/dev/null 2>&1
    log_info "Bucket '$STATE_BUCKET' created successfully"
  fi
}

state_init() {
  ensure_bucket_exists

  if ! aws s3api head-object \
      --bucket "$STATE_BUCKET" \
      --key "$STATE_KEY" \
      --region "$AWS_REGION" >/dev/null 2>&1; then

    log_info "Initializing remote state"
    cat > "$STATE_LOCAL" <<EOF
{
  "project": "aws-project",
  "region": "$AWS_REGION",
  "resources": {
    "ec2": {},
    "security_group": {},
    "keypair": {},
    "s3": {}
  }
}
EOF
    aws s3 cp "$STATE_LOCAL" "s3://$STATE_BUCKET/$STATE_KEY" >/dev/null 2>&1
    log_info "Remote state initialized at s3://$STATE_BUCKET/$STATE_KEY"
  fi

  # ensure local state exists
  state_pull || {
    cat > "$STATE_LOCAL" <<EOF
{
  "project": "aws-project",
  "region": "$AWS_REGION",
  "resources": {
    "ec2": {},
    "security_group": {},
    "keypair": {},
    "s3": {}
  }
}
EOF
  }
}

state_pull() {
  ensure_bucket_exists
  if ! aws s3 cp "s3://$STATE_BUCKET/$STATE_KEY" "$STATE_LOCAL" >/dev/null 2>&1; then
    log_warn "No remote state found. Creating empty local state."
    cat > "$STATE_LOCAL" <<EOF
{
  "project": "aws-project",
  "region": "$AWS_REGION",
  "resources": {
    "ec2": {},
    "security_group": {},
    "keypair": {},
    "s3": {}
  }
}
EOF
  fi
}

state_push() {
  aws s3 cp "$STATE_LOCAL" "s3://$STATE_BUCKET/$STATE_KEY" >/dev/null 2>&1
}

_state_add() {
  local resource="$1" id="$2" payload="$3"
  state_pull
  jq --arg r "$resource" --arg id "$id" --argjson p "$payload" \
    '.resources[$r][$id] = $p' "$STATE_LOCAL" > "$STATE_LOCAL.tmp"
  mv "$STATE_LOCAL.tmp" "$STATE_LOCAL"
  state_push
}

_state_delete() {
  local resource="$1" id="$2"
  state_pull
  jq --arg r "$resource" --arg id "$id" \
    'del(.resources[$r][$id])' "$STATE_LOCAL" > "$STATE_LOCAL.tmp"
  mv "$STATE_LOCAL.tmp" "$STATE_LOCAL"
  state_push
}

state_list() {
  local resource="$1"
  state_pull
  jq -r ".resources[$resource] // {} | keys[]" "$STATE_LOCAL"
}

# ============================================================
# Resource helpers
# ============================================================
sg_create() { local name="$1"
  sg_id=$(aws ec2 create-security-group \
    --group-name "$name" \
    --description "Managed by state_manager" \
    --region "$AWS_REGION" \
    --query GroupId --output text)
  payload=$(jq -n --arg name "$name" --arg created "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '{name:$name,created_at:$created}')
  _state_add "security_group" "$sg_id" "$payload"
  echo "$sg_id"
}

sg_delete() { local id="$1"
  log_warn "Deleting security group: $id"
  aws ec2 delete-security-group --group-id "$id"
  _state_delete "security_group" "$id"
}

keypair_create() { local name="$1"
  aws ec2 create-key-pair --key-name "$name" --query KeyMaterial --output text > "$name.pem"
  chmod 400 "$name.pem"
  payload=$(jq -n --arg name "$name" --arg created "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '{name:$name,created_at:$created}')
  _state_add "keypair" "$name" "$payload"
}

keypair_delete() { local name="$1"
  log_warn "Deleting keypair: $name"
  aws ec2 delete-key-pair --key-name "$name"
  _state_delete "keypair" "$name"
  [[ -f "$name.pem" ]] && rm -f "$name.pem"
}

ec2_create() { local name="$1" ami="$2" type="$3" sg="$4" key="$5"
  instance_id=$(aws ec2 run-instances \
    --image-id "$ami" \
    --instance-type "$type" \
    --security-group-ids "$sg" \
    --key-name "$key" \
    --query 'Instances[0].InstanceId' \
    --output text)
  payload=$(jq -n --arg name "$name" --arg ami "$ami" --arg type "$type" --arg sg "$sg" --arg key "$key" --arg created "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '{name:$name,ami:$ami,instance_type:$type,security_group:$sg,keypair:$key,created_at:$created}')
  _state_add "ec2" "$instance_id" "$payload"
  echo "$instance_id"
}

ec2_delete() { local id="$1"
  log_warn "Terminating EC2: $id"
  aws ec2 terminate-instances --instance-ids "$id"
  _state_delete "ec2" "$id"
}

s3_track() { local bucket="$1"
  payload=$(jq -n --arg bucket "$bucket" --arg created "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" '{bucket:$bucket,created_at:$created}')
  _state_add "s3" "$bucket" "$payload"
}

s3_untrack() { local bucket="$1"
  _state_delete "s3" "$bucket"
}

# ============================================================
# Entry guard
# ============================================================
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "This is a library. Source it, do not execute directly."
  exit 1
fi
