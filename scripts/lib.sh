#!/usr/bin/env bash
# Utilidades comunes de los scripts de LAB-98.
set -euo pipefail

# pwd -W devuelve la ruta Windows en Git Bash (terraform.exe no entiende /c/...); en Linux/macOS usa pwd.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && { pwd -W 2>/dev/null || pwd; })"
ENV_NAME="${ENV:-local}"
# Cada ambiente tiene su raíz en terraform/envs/<ENV>; ENV_DIR permite reutilizar una raíz (p. ej. para probar
# el aislamiento de estados con otro ENV). El estado del bootstrap es un archivo local distinto por ambiente.
ENV_DIR="${ENV_DIR:-$ROOT/terraform/envs/$ENV_NAME}"
BOOT_STATE="terraform.$ENV_NAME.tfstate"
EMULATOR_URL="${EMULATOR_URL:-http://localhost:4566}"

# Docker en Git Bash convierte rutas tipo /etc/...; lo desactivamos para docker exec.
export MSYS_NO_PATHCONV=1

log() { printf '[shoplab-infra] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

# Espera a que Floci responda; falla con un mensaje claro si no lo hace.
wait_for_emulator() {
  local tries=60
  until curl -fsS "$EMULATOR_URL/_localstack/health" >/dev/null 2>&1; do
    tries=$((tries - 1))
    [ "$tries" -gt 0 ] || die "Floci no responde en $EMULATOR_URL (¿puerto 4566 ocupado o contenedor caído?)"
    sleep 2
  done
}
