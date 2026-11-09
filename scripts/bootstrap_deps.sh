#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REQ_FILE="$ROOT_DIR/host/python/requirements.txt"

AUTO_INSTALL=true
SETUP_PYTHON=true
RUN_SMOKE=true
CHECK_ONLY=false

usage() {
  cat <<USAGE
Usage: $0 [options]

Options:
  --check-only      Check dependencies only (no installs)
  --no-auto-install Do not install missing system packages
  --no-python       Skip Python virtualenv and pip install
  --skip-smoke      Skip dry-run correctness smoke test
  -h, --help        Show this help
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only)
      CHECK_ONLY=true
      AUTO_INSTALL=false
      SETUP_PYTHON=false
      RUN_SMOKE=false
      shift
      ;;
    --no-auto-install)
      AUTO_INSTALL=false
      shift
      ;;
    --no-python)
      SETUP_PYTHON=false
      shift
      ;;
    --skip-smoke)
      RUN_SMOKE=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

log() {
  echo "[bootstrap] $*"
}

warn() {
  echo "[bootstrap] WARNING: $*" >&2
}

has_cmd() {
  command -v "$1" >/dev/null 2>&1
}

has_tool() {
  local tool="$1"
  if command -v "$tool" >/dev/null 2>&1; then
    return 0
  fi
  if [[ -x "$ROOT_DIR/.venv/bin/$tool" ]]; then
    return 0
  fi
  return 1
}

install_system_packages() {
  local -a pkgs=(build-essential cmake make python3 python3-pip python3-venv)

  if ! has_cmd apt-get; then
    warn "apt-get not found; cannot auto-install system packages on this OS."
    return 1
  fi

  local -a prefix=()
  if [[ "$(id -u)" -ne 0 ]]; then
    if has_cmd sudo; then
      prefix=(sudo)
    else
      warn "sudo not available and not running as root; cannot install system packages."
      return 1
    fi
  fi

  log "Installing system packages: ${pkgs[*]}"
  "${prefix[@]}" apt-get update
  "${prefix[@]}" apt-get install -y "${pkgs[@]}"
}

check_required_commands() {
  local -a required=(bash make g++ python3 cmake)
  local -a recommended=()
  local -a missing_required=()
  local -a missing_recommended=()

  for cmd in "${required[@]}"; do
    if ! has_tool "$cmd"; then
      missing_required+=("$cmd")
    fi
  done

  if [[ ${#missing_required[@]} -gt 0 ]]; then
    warn "Missing required commands: ${missing_required[*]}"
    return 1
  fi

  for cmd in "${recommended[@]}"; do
    if ! has_tool "$cmd"; then
      missing_recommended+=("$cmd")
    fi
  done

  if [[ ${#missing_recommended[@]} -gt 0 ]]; then
    warn "Missing recommended commands: ${missing_recommended[*]}"
  fi

  return 0
}

check_toolchain_hints() {
  set -a
  source "$ROOT_DIR/config/project.env"
  set +a

  if [[ -n "${VITIS_SETTINGS:-}" && -f "${VITIS_SETTINGS}" ]]; then
    log "Found Vitis settings: ${VITIS_SETTINGS}"
  else
    warn "Vitis settings not found at VITIS_SETTINGS=${VITIS_SETTINGS:-unset}"
  fi

  if [[ -n "${VIVADO_SETTINGS:-}" && -f "${VIVADO_SETTINGS}" ]]; then
    log "Found Vivado settings: ${VIVADO_SETTINGS}"
  else
    warn "Vivado settings not found at VIVADO_SETTINGS=${VIVADO_SETTINGS:-unset}"
  fi

  if has_cmd v++; then
    log "Found v++ in PATH"
  else
    warn "v++ not found in PATH (needed for xo/xclbin build)"
  fi

  if has_cmd vitis_hls || has_cmd vitis-run; then
    log "Found Vitis HLS command in PATH"
  else
    warn "vitis_hls/vitis-run not found in PATH"
  fi

  if has_cmd vivado; then
    log "Found vivado in PATH"
  else
    warn "vivado not found in PATH"
  fi
}

setup_python_venv() {
  if ! has_cmd python3; then
    warn "python3 not found; cannot create virtualenv"
    return 1
  fi

  if [[ ! -d "$ROOT_DIR/.venv" ]]; then
    log "Creating Python virtualenv at $ROOT_DIR/.venv"
    python3 -m venv "$ROOT_DIR/.venv"
  fi

  local py_bin="$ROOT_DIR/.venv/bin/python"
  if [[ ! -x "$py_bin" ]]; then
    warn "virtualenv python not found at $py_bin"
    return 1
  fi

  log "Installing Python dependencies from $REQ_FILE"
  "$py_bin" -m pip install --upgrade pip
  "$py_bin" -m pip install -r "$REQ_FILE"

  if ! has_tool cmake; then
    log "Installing local cmake into virtualenv"
    "$py_bin" -m pip install cmake
  fi
}

run_checks_only() {
  log "Running dependency checks (check-only mode)"
  if ! check_required_commands; then
    return 1
  fi
  check_toolchain_hints
  log "Dependency checks completed"
}

if $CHECK_ONLY; then
  run_checks_only
  exit 0
fi

if ! check_required_commands; then
  if $AUTO_INSTALL; then
    if ! install_system_packages; then
      warn "System package install failed; trying local Python-based fallback."
    fi
  else
    warn "Auto-install is disabled and required commands are missing."
    exit 1
  fi
fi

if $SETUP_PYTHON; then
  setup_python_venv
fi

check_required_commands
check_toolchain_hints

if $RUN_SMOKE; then
  log "Running dry-run smoke test"
  "$ROOT_DIR/scripts/run_correctness.sh"
fi

log "Bootstrap complete"
