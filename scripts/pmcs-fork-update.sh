#!/usr/bin/env bash
set -euo pipefail

SPOOLMAN_GH_REPO="${SPOOLMAN_GH_REPO:-displaced/Spoolman}"
SPOOLMAN_GH_BRANCH="${SPOOLMAN_GH_BRANCH:-master}"
PYTHON_VERSION="${PYTHON_VERSION:-3.14}"
SPOOLMAN_API_URL="${SPOOLMAN_API_URL:-/api/v1}"

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

ensure_node_20() {
  local need_node="yes"
  if command -v node >/dev/null 2>&1; then
    local major
    major="$(node -v | sed 's/^v//' | cut -d. -f1)"
    if [[ "${major}" -ge 20 ]]; then
      need_node="no"
    fi
  fi

  if [[ "${need_node}" == "yes" ]]; then
    info "Installing Node.js 20.x for client build"
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    apt-get install -y ca-certificates curl
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
  fi
}

copy_client_dist_from_current() {
  if [[ -d "${APP_DIR}/client/dist" ]]; then
    info "Reusing existing client/dist from current install"
    mkdir -p "${NEW_DIR}/client"
    rm -rf "${NEW_DIR}/client/dist"
    cp -a "${APP_DIR}/client/dist" "${NEW_DIR}/client/dist"
    ok "Reused client dist from current install"
    return 0
  fi

  return 1
}

build_client_if_needed() {
  if [[ -d "${NEW_DIR}/client/dist" ]]; then
    ok "Client dist already present"
    return
  fi

  if copy_client_dist_from_current; then
    return
  fi

  info "Building client/dist"
  ensure_node_20
  cd "${NEW_DIR}/client"
  npm ci
  if ! NODE_OPTIONS="${NODE_OPTIONS:---max-old-space-size=768}" VITE_APIURL="${SPOOLMAN_API_URL}" npm run build; then
    if copy_client_dist_from_current; then
      info "Client build failed, used previous dist instead"
      return
    fi

    err "Client build failed and no previous dist is available"
    exit 1
  fi
  ok "Client dist built"
}

ensure_backend_runtime() {
  info "Verifying backend runtime dependencies"
  if .venv/bin/python -c "import uvicorn, fastapi, alembic" >/dev/null 2>&1; then
    ok "Backend runtime dependencies available"
    return
  fi

  info "Locked sync appears incomplete, retrying unlocked sync"
  uv sync

  if ! .venv/bin/python -c "import uvicorn, fastapi, alembic" >/dev/null 2>&1; then
    err "Backend runtime dependencies are still missing after fallback sync"
    exit 1
  fi

  ok "Backend runtime dependencies repaired"
}

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
ensure_backend_runtime

build_client_if_needed

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
echo "API URL: ${SPOOLMAN_API_URL}"
