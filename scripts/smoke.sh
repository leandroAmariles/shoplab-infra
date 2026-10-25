#!/usr/bin/env bash
# Prueba de humo: apply completo sobre Floci, espera a que todas las Application de Argo CD estén Synced y Healthy
# y destruye. El destroy y la limpieza se ejecutan siempre (trap), incluso si algo falla o se cancela.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v kubectl >/dev/null || die "kubectl no está instalado"

# shellcheck disable=SC1091
set -a; source "$ROOT/versions.env"; set +a
KUBECONFIG_FILE="$ENV_DIR/kubeconfig.yaml"

# Solo se valida el despliegue: si no hay valores de secretos, valen marcadores obvios.
if [ ! -f "$ENV_DIR/secrets.auto.tfvars" ] && [ -z "${TF_VAR_secrets:-}" ]; then
  export TF_VAR_secrets='{"postgres-password"="CHANGE_ME","llm-api-key"="CHANGE_ME"}'
fi

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
  bash "$ROOT/scripts/down.sh" || { log "down.sh falló; se fuerza la limpieza"; bash "$ROOT/scripts/verify-clean.sh" || status=1; }
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
