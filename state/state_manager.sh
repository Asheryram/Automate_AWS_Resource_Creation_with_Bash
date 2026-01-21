#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Configuration
# ============================================================
AWS_REGION="${AWS_REGION:-eu-central-1}"
STATE_BUCKET="${STATE_BUCKET:-aws-project-state}"
STATE_KEY="${STATE_KEY:-state.json}"
STATE_LOCAL="/tmp/$STATE_KEY"

LOG_LEVEL="${LOG_LEVEL:-INFO}"
CONSOLE_LOG="${CONSOLE_LOG:-true}"

# ============================================================
# Logger
# ============================================================
level_to_num() {
  case "$1" in
    DEBUG) echo 0 ;;
    DRYRUN) echo 2 ;;
    INFO) echo 2 ;;
    WARN) echo 3 ;;
    ERROR) echo 4 ;;
    *) echo 2 ;;
  esac
}

log() {
  local level="$1" msg="$2"
  local now level_num msg_num
  now=$(date '+%Y-%m-%d %H:%M:%S')
  level_num=$(level_to_num "$LOG_LEVEL")
  msg_num=$(level_to_num "$level")

  (( msg_num < level_num )) && return

  local line="[$now] [$level] $msg"

  [[ "$CONSOLE_LOG" == "true" ]] && echo "$line"
  echo "$line" >> aws_project.log 2>/dev/null
}

log_info() { log INFO "$1"; }
log_warn() { log WARN "$1"; }
log_error(){ log ERROR "$1"; }

# ============================================================
# Requirements
# ============================================================
require_jq() {
  command -v jq >/dev/null || {
    log_error "jq is required for state operations"
    exit 1
  }
}

command -v aws >/dev/null || { echo "aws cli required"; exit 1; }
 require_jq
# ============================================================
# State Backend
# ============================================================
state_init() {
  if ! aws s3api head-object \
      --bucket "$STATE_BUCKET" \
      --key "$STATE_KEY" \
      --region "$AWS_REGION" 2>/dev/null; then

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

    aws s3 cp "$STATE_LOCAL" "s3://$STATE_BUCKET/$STATE_KEY"
  fi
}

state_pull() {
  aws s3 cp "s3://$STATE_BUCKET/$STATE_KEY" "$STATE_LOCAL" >/dev/null
}

state_push() {
  aws s3 cp "$STATE_LOCAL" "s3://$STATE_BUCKET/$STATE_KEY" >/dev/null
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
  jq "del(.resources[$resource][$id])" "$STATE_LOCAL" > "$STATE_LOCAL.tmp"
  mv "$STATE_LOCAL.tmp" "$STATE_LOCAL"
  state_push
}

state_list() {
  local resource="$1"
  state_pull
  jq -r ".resources[$resource] | keys[]" "$STATE_LOCAL"
}

# ============================================================
# Security Group
# ============================================================
sg_create() {
  local name="$1"
  log_info "Creating security group: $name"

  sg_id=$(aws ec2 create-security-group \
    --group-name "$name" \
    --description "Managed by state_manager" \
    --region "$AWS_REGION" \
    --query GroupId --output text)

  payload=$(jq -n \
    --arg name "$name" \
    --arg created "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{name:$name, created_at:$created}')

  _state_add "security_group" "$sg_id" "$payload"
  echo "$sg_id"
}

sg_delete() {
  local id="$1"
  log_warn "Deleting security group: $id"
  aws ec2 delete-security-group --group-id "$id"
  _state_delete "security_group" "$id"
}

# ============================================================
# Key Pair
# ============================================================
keypair_create() {
  local name="$1"
  log_info "Creating keypair: $name"

  aws ec2 create-key-pair \
    --key-name "$name" \
    --query KeyMaterial \
    --output text > "$name.pem"

  chmod 400 "$name.pem"

  payload=$(jq -n \
    --arg name "$name" \
    --arg created "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{name:$name, created_at:$created}')

  _state_add "keypair" "$name" "$payload"
}

keypair_delete() {
  local name="$1"
  log_warn "Deleting keypair: $name"
  aws ec2 delete-key-pair --key-name "$name"
  _state_delete "keypair" "$name"
}

# ============================================================
# EC2
# ============================================================
ec2_create() {
  local name="$1" ami="$2" type="$3" sg="$4" key="$5"
  log_info "Launching EC2: $name"

  instance_id=$(aws ec2 run-instances \
    --image-id "$ami" \
    --instance-type "$type" \
    --security-group-ids "$sg" \
    --key-name "$key" \
    --query 'Instances[0].InstanceId' \
    --output text)

  payload=$(jq -n \
    --arg name "$name" \
    --arg ami "$ami" \
    --arg type "$type" \
    --arg sg "$sg" \
    --arg key "$key" \
    --arg created "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{
      name:$name,
      ami:$ami,
      instance_type:$type,
      security_group:$sg,
      keypair:$key,
      created_at:$created
    }')

  _state_add "ec2" "$instance_id" "$payload"
  echo "$instance_id"
}

ec2_delete() {
  local id="$1"
  log_warn "Terminating EC2: $id"
  aws ec2 terminate-instances --instance-ids "$id"
  _state_delete "ec2" "$id"
}

# ============================================================
# S3 (track only)
# ============================================================
s3_track() {
  local bucket="$1"
  payload=$(jq -n \
    --arg bucket "$bucket" \
    --arg created "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{bucket:$bucket, created_at:$created}')
  _state_add "s3" "$bucket" "$payload"
}

s3_untrack() {
  local bucket="$1"
  _state_delete "s3" "$bucket"
}

# ============================================================
# Entry Guard
# ============================================================
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  echo "This file is a library. Source it, do not execute directly."
  exit 1
fi
