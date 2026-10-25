#!/usr/bin/env bash
# Busca credenciales en el historial y en los cambios en staging con gitleaks (vía Docker, sin instalar nada).
# Los archivos ignorados por git (kubeconfig.yaml, secrets.auto.tfvars) no se escanean: no pueden llegar al repositorio.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v docker >/dev/null || die "Docker no está instalado"
IMAGE="zricethezav/gitleaks:v8.30.1"

run_gitleaks() {
  docker run --rm -v "$ROOT:/repo" "$IMAGE" "$@" --config /repo/.gitleaks.toml --no-banner --redact
}

log "escaneando el historial"
run_gitleaks git /repo
log "escaneando los cambios en staging"
run_gitleaks git /repo --staged
log "sin credenciales"
