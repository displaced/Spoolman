#!/usr/bin/env bash
set -euo pipefail

# Run on Proxmox host. This wraps the official PMCS Spoolman CT creator
# and then installs Spoolman from your fork/branch inside the selected CT.

SPOOLMAN_GH_REPO="${SPOOLMAN_GH_REPO:-displaced/Spoolman}"
SPOOLMAN_GH_BRANCH="${SPOOLMAN_GH_BRANCH:-master}"
TARGET_CTID="${TARGET_CTID:-}"

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

info() { echo -e "${YELLOW}[INFO]${NC} $*"; }
ok() { echo -e "${GREEN}[OK]${NC}   $*"; }
err() { echo -e "${RED}[ERR]${NC}  $*" >&2; }

if [[ $EUID -ne 0 ]]; then
  err "Run this on the Proxmox host as root."
  exit 1
fi

if ! command -v pct >/dev/null 2>&1; then
  err "pct command not found. This must be run on a Proxmox host."
  exit 1
fi

if [[ -z "${TARGET_CTID}" ]]; then
  info "Launching official PMCS Spoolman script to create the container"
  export var_ram="${var_ram:-2048}"
  bash -c "$(curl -fsSL https://raw.githubusercontent.com/community-scripts/ProxmoxVE/main/ct/spoolman.sh)"

  echo
  read -r -p "Enter the CTID of the newly created Spoolman container: " TARGET_CTID
fi

if [[ -z "${TARGET_CTID}" ]]; then
  err "No CTID provided."
  exit 1
fi

if ! pct status "${TARGET_CTID}" >/dev/null 2>&1; then
  err "Container ${TARGET_CTID} does not exist."
  exit 1
fi

if [[ "$(pct status "${TARGET_CTID}" | awk '{print $2}')" != "running" ]]; then
  info "Starting container ${TARGET_CTID}"
  pct start "${TARGET_CTID}"
fi

info "Installing forked Spoolman in CT ${TARGET_CTID}"
pct exec "${TARGET_CTID}" -- bash -lc "SPOOLMAN_GH_REPO='${SPOOLMAN_GH_REPO}' SPOOLMAN_GH_BRANCH='${SPOOLMAN_GH_BRANCH}' bash <(curl -fsSL https://raw.githubusercontent.com/${SPOOLMAN_GH_REPO}/${SPOOLMAN_GH_BRANCH}/scripts/pmcs-fork-install.sh)"

ok "Fork install completed in CT ${TARGET_CTID}"
echo "Repo:   ${SPOOLMAN_GH_REPO}"
echo "Branch: ${SPOOLMAN_GH_BRANCH}"
