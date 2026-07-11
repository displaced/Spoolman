#!/usr/bin/env bash
set -euo pipefail

SPOOLMAN_GH_REPO="${SPOOLMAN_GH_REPO:-displaced/Spoolman}"
SPOOLMAN_GH_BRANCH="${SPOOLMAN_GH_BRANCH:-master}"
PYTHON_VERSION="${PYTHON_VERSION:-3.14}"

APP_DIR="/opt/spoolman"
NEW_DIR="/opt/spoolman_new"
BAK_DIR="/opt/spoolman_bak"

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
NC='\033[0m'

info() { echo -e "${YELLOW}[INFO]${NC} $*"; }
ok() { echo -e "${GREEN}[OK]${NC}   $*"; }
err() { echo -e "${RED}[ERR]${NC}  $*" >&2; }

if [[ $EUID -ne 0 ]]; then
  err "Run as root inside the container."
  exit 1
fi

if [[ ! -d "${APP_DIR}" ]]; then
  err "No existing installation found at ${APP_DIR}."
  exit 1
fi

if [[ ! -f "${APP_DIR}/.env" ]]; then
  err "Missing ${APP_DIR}/.env. Refusing to continue."
  exit 1
fi

info "Stopping spoolman service"
systemctl stop spoolman || true

info "Cloning ${SPOOLMAN_GH_REPO}@${SPOOLMAN_GH_BRANCH}"
rm -rf "${NEW_DIR}"
git clone --depth 1 --branch "${SPOOLMAN_GH_BRANCH}" \
  "https://github.com/${SPOOLMAN_GH_REPO}.git" "${NEW_DIR}"

if ! command -v uv >/dev/null 2>&1; then
  info "Installing uv"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="/root/.local/bin:${PATH}"
fi

info "Syncing dependencies"
cd "${NEW_DIR}"
uv python install "${PYTHON_VERSION}" >/dev/null 2>&1 || true
uv sync --locked --no-install-project
uv sync --locked

info "Preserving .env"
cp "${APP_DIR}/.env" "${NEW_DIR}/.env"

info "Swapping directories"
rm -rf "${BAK_DIR}"
mv "${APP_DIR}" "${BAK_DIR}"
mv "${NEW_DIR}" "${APP_DIR}"

if [[ -f /etc/systemd/system/spoolman.service ]]; then
  sed -i 's|^ExecStart=.*|ExecStart=/usr/bin/bash /opt/spoolman/scripts/start.sh|' /etc/systemd/system/spoolman.service
fi

systemctl daemon-reload
systemctl enable -q spoolman || true
systemctl start spoolman

ok "Fork update complete"
echo "Repo:   ${SPOOLMAN_GH_REPO}"
echo "Branch: ${SPOOLMAN_GH_BRANCH}"
