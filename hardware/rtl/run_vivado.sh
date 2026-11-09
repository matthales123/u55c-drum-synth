#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RTL_DIR="$ROOT_DIR/hardware/rtl"

set -a
source "$ROOT_DIR/config/project.env"
set +a

if [[ -z "${VIVADO_SETTINGS:-}" || ! -f "${VIVADO_SETTINGS}" ]]; then
  echo "ERROR: set VIVADO_SETTINGS in config/project.env (current: ${VIVADO_SETTINGS:-unset})" >&2
  exit 1
fi

export PYTHONPATH="${PYTHONPATH:-}"
export MATLABPATH="${MATLABPATH:-}"
source "$VIVADO_SETTINGS"

cd "$RTL_DIR"
vivado -mode batch -source scripts/project.tcl
