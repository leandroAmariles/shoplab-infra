#!/usr/bin/env bash
# Prueba de humo: apply completo sobre Floci, espera a que todas las Application de Argo CD estén Synced y Healthy
# y destruye. El destroy y la limpieza se ejecutan siempre (trap), incluso si algo falla o se cancela.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v kubectl >/dev/null || die "kubectl no está instalado"

# shellcheck disable=SC1091
set -a; source "$ROOT/versions.env"; set +a
KUBECONFIG_FILE="$ENV_DIR/kubeconfig.yaml"

use_placeholder_secrets_if_missing

kc() { kubectl --kubeconfig "$KUBECONFIG_FILE" "$@"; }

report_failure() {
  log "estado de las aplicaciones de Argo CD:"
  kc get applications -A 2>&1 || true
  log "eventos recientes:"
  kc get events -A --sort-by=.lastTimestamp 2>&1 | tail -n 30 || true
}

cleanup() {
  status=$?
  [ "$status" -eq 0 ] || report_failure
  log "destruyendo el entorno y limpiando (código previo: $status)"
  if ! bash "$ROOT/scripts/down.sh"; then
    # Con el clúster dañado terraform destroy puede fallar: se eliminan los contenedores y redes a la fuerza.
    log "down.sh falló; se fuerza la limpieza"
    docker compose -f "$ROOT/docker-compose.yml" down --remove-orphans >/dev/null 2>&1 || true
    docker ps -aq --filter 'name=^floci-aws-' | xargs -r docker rm -f >/dev/null 2>&1 || true
    docker network ls --format '{{.Name}}' | grep -E '^(floci-aws-|shoplab-infra_default$)'       | xargs -r docker network rm >/dev/null 2>&1 || true
    bash "$ROOT/scripts/verify-clean.sh" || status=1
  fi
  exit "$status"
}
trap cleanup EXIT

bash "$ROOT/scripts/up.sh"

log "esperando a Argo CD (Synced + Healthy), máximo ${ARGOCD_TIMEOUT}s"
deadline=$((SECONDS + ARGOCD_TIMEOUT))
while :; do
  total="$(kc get applications -n argocd --no-headers 2>/dev/null | wc -l | tr -d ' ')"
  ready="$(kc get applications -n argocd \
    -o jsonpath='{range .items[*]}{.status.sync.status}/{.status.health.status}{"\n"}{end}' 2>/dev/null \
    | grep -c '^Synced/Healthy$' || true)"
  if [ "$total" -gt 0 ] && [ "$ready" -eq "$total" ]; then
    log "Argo CD listo: $ready/$total aplicaciones Synced y Healthy"
    break
  fi
  if [ "$SECONDS" -ge "$deadline" ]; then
    die "Argo CD no quedó Synced y Healthy en ${ARGOCD_TIMEOUT}s ($ready/$total aplicaciones listas)"
  fi
  sleep 10
done
