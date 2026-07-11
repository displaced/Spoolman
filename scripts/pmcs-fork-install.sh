#!/usr/bin/env bash
set -euo pipefail

SPOOLMAN_GH_REPO="${SPOOLMAN_GH_REPO:-displaced/Spoolman}"
SPOOLMAN_GH_BRANCH="${SPOOLMAN_GH_BRANCH:-master}"
PYTHON_VERSION="${PYTHON_VERSION:-3.14}"

APP_DIR="/opt/spoolman"
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

export DEBIAN_FRONTEND=noninteractive

info "Installing dependencies"
apt-get update -y
apt-get install -y \
  ca-certificates \
  curl \
  git \
  build-essential \
  libpq-dev \
  libffi-dev
ok "Dependencies installed"

if ! command -v uv >/dev/null 2>&1; then
  info "Installing uv"
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="/root/.local/bin:${PATH}"
fi
ok "uv available"

if [[ -d "${APP_DIR}" ]]; then
  info "Existing installation found, backing up to ${BAK_DIR}"
  rm -rf "${BAK_DIR}"
  mv "${APP_DIR}" "${BAK_DIR}"
fi

info "Cloning ${SPOOLMAN_GH_REPO}@${SPOOLMAN_GH_BRANCH}"
git clone --depth 1 --branch "${SPOOLMAN_GH_BRANCH}" \
  "https://github.com/${SPOOLMAN_GH_REPO}.git" "${APP_DIR}"
ok "Repository cloned"

info "Setting up virtual environment and dependencies"
cd "${APP_DIR}"
uv python install "${PYTHON_VERSION}" >/dev/null 2>&1 || true
uv sync --locked --no-install-project
uv sync --locked
ok "Dependencies synced"

if [[ -f "${BAK_DIR}/.env" ]]; then
  cp "${BAK_DIR}/.env" "${APP_DIR}/.env"
  ok "Reused existing .env"
elif [[ -f "${APP_DIR}/.env.example" ]]; then
  cp "${APP_DIR}/.env.example" "${APP_DIR}/.env"
  ok "Created .env from .env.example"
else
  err "No .env.example found in branch; create ${APP_DIR}/.env manually."
  exit 1
fi

info "Creating/refreshing systemd service"
cat >/etc/systemd/system/spoolman.service <<'EOF'
[Unit]
Description=Spoolman
After=network.target

[Service]
Type=simple
WorkingDirectory=/opt/spoolman
EnvironmentFile=/opt/spoolman/.env
ExecStart=/usr/bin/bash /opt/spoolman/scripts/start.sh
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable -q --now spoolman
ok "Service started"

ok "Fork install complete"
echo "Repo:   ${SPOOLMAN_GH_REPO}"
echo "Branch: ${SPOOLMAN_GH_BRANCH}"
