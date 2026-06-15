#!/usr/bin/env bash
# =============================================================
# common.sh — Shared config extraction for K8s lab scripts
# Prefers terraform output (robust), falls back to tfvars parsing
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TERRAFORM_DIR="${PROJECT_DIR}/terraform"
TFVARS="${TERRAFORM_DIR}/terraform.tfvars"

# --- Extract config from terraform output (primary) or tfvars (fallback) ---
# Terraform output is the robust method: Terraform parses its own HCL
# The tfvars fallback uses simple awk/grep (works for standard formatting)
_load_config() {
  local _cp_ip="" _worker_ips="" _ssh_user=""

  # --- Primary: terraform output ---
  if [ -f "${TERRAFORM_DIR}/terraform.tfstate" ]; then
    _cp_ip=$(
      cd "$TERRAFORM_DIR" && terraform output -raw control_plane_ip 2>/dev/null
    ) || true
    _ssh_user=$(
      cd "$TERRAFORM_DIR" && terraform output -raw ssh_user 2>/dev/null
    ) || true
    local _wjson
    _wjson=$(
      cd "$TERRAFORM_DIR" && terraform output -json worker_ips 2>/dev/null
    ) || true
    if [ -n "$_wjson" ]; then
      _worker_ips=$(echo "$_wjson" | jq -r '.[]' | paste -sd ' ' 2>/dev/null) || true
    fi
  fi

  # --- Fallback: parse terraform.tfvars ---
  if [ -z "$_cp_ip" ] && [ -f "$TFVARS" ]; then
    _cp_ip=$(awk -F'"' '/^control_plane_ip/{print $2}' "$TFVARS")
  fi
  if [ -z "$_worker_ips" ] && [ -f "$TFVARS" ]; then
    # Extract list items: ["ip1", "ip2"] → "ip1 ip2"
    _worker_ips=$(awk '/^worker_ips/{gsub(/[\[\]",]/, ""); $1=$1; print $3, $4}' "$TFVARS")
  fi
  if [ -z "$_ssh_user" ] && [ -f "$TFVARS" ]; then
    _ssh_user=$(awk -F'"' '/^ssh_user/{print $2}' "$TFVARS")
  fi

  # --- Defaults ---
  CP_IP="${_cp_ip:-192.168.1.231}"
  WORKER_IPS="${_worker_ips:-192.168.1.232 192.168.1.233}"
  SSH_USER="${_ssh_user:-ubuntu}"
}

_load_config