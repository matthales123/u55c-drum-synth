#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_TAG="$(basename "$ROOT_DIR")"
PORT="${1:-${WEB_PORT:-9890}}"
PROTO="${WEB_PROTO:-tcp}"
RULE="${PORT}/${PROTO}"
COMMENT_TAG="${PROJECT_TAG}_webapp_${PORT}"

log() {
  echo "[firewall] $*"
}

if ! command -v ufw >/dev/null 2>&1; then
  log "ufw is not installed; skipping firewall update."
  exit 0
fi

SUDO=()
if [[ "$(id -u)" -ne 0 ]]; then
  if sudo -n true >/dev/null 2>&1; then
    SUDO=(sudo -n)
  else
    log "sudo authentication is required to update ufw rules."
    log "Run this once, then relaunch:"
    log "  sudo ufw allow ${RULE} comment '${COMMENT_TAG}'"
    exit 0
  fi
fi

UFW_STATUS="$("${SUDO[@]}" ufw status 2>/dev/null || true)"
if [[ "$UFW_STATUS" == *"Status: inactive"* ]]; then
  log "ufw is installed but inactive; skipping firewall update."
  exit 0
fi

if grep -Eq "(^|[[:space:]])${PORT}/${PROTO}([[:space:]]|$)" <<<"$UFW_STATUS"; then
  log "Rule already present for ${RULE}."
  exit 0
fi

"${SUDO[@]}" ufw allow "${RULE}" comment "${COMMENT_TAG}" >/dev/null
log "Added ufw allow rule for ${RULE}."
