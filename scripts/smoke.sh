#!/usr/bin/env bash
# Prueba de humo: apply completo sobre Floci, espera a que la Application raíz y la de dev de Argo CD estén Synced y
# Healthy (y a que la raíz haya creado las de staging y prod) y destruye. El destroy y la limpieza se ejecutan siempre (trap), incluso si algo falla o se cancela.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v kubectl >/dev/null || die "kubectl no está instalado"

# shellcheck disable=SC1091
set -a; source "$ROOT/versions.env"; set +a
KUBECONFIG_FILE="$ENV_DIR/kubeconfig.yaml"
export APPLY_TIMEOUT DESTROY_TIMEOUT

use_placeholder_secrets_if_missing

kc() { kubectl --kubeconfig "$KUBECONFIG_FILE" "$@"; }

report_failure() {
  log "estado de las aplicaciones de Argo CD:"
  kc get applications -A 2>&1 || true
  log "eventos recientes:"
  kc get events -A --sort-by=.lastTimestamp 2>&1 | tail -n 30 || true
}

# Estado de Docker y de Floci para diagnosticar un destroy que falla o se agota.
report_docker() {
  log "contenedores:"
  docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Networks}}' 2>&1 || true
  log "redes de Floci y contenedores conectados:"
  docker network ls --format '{{.Name}}' | grep -E '^(floci-aws-|shoplab-infra_)' | while read -r net; do
    docker network inspect "$net" --format '{{.Name}}: {{range .Containers}}{{.Name}} {{end}}' 2>&1 || true
  done
  log "últimas líneas del log de Floci:"
  docker logs --tail 60 shoplab-floci 2>&1 || true
}

# En el Docker Engine de Linux del runner de CI, DeleteVpc de Floci no responde aunque todo lo demás ya esté destruido
# (en local tarda 1 s). Si el destroy se agota y lo único que queda en el estado es la VPC, se avisa y se sigue: el
# emulador se desecha de todos modos. Cualquier otro recurso pendiente sí hace fallar la prueba.
only_vpc_left() {
  local remaining
  remaining="$(terraform -chdir="$ENV_DIR" state list 2>/dev/null || true)"
  [ "$remaining" = 'module.eks.aws_vpc.this[0]' ]
}

# Con el emulador dañado terraform destroy no termina: se eliminan los contenedores y redes a la fuerza.
force_cleanup() {
  docker compose -f "$ROOT/docker-compose.yml" down --remove-orphans >/dev/null 2>&1 || true
  docker ps -aq --filter 'name=^floci-aws-' | xargs -r docker rm -f >/dev/null 2>&1 || true
  docker network ls --format '{{.Name}}' | grep -E '^(floci-aws-|shoplab-infra_default$)' \
    | xargs -r docker network rm >/dev/null 2>&1 || true
  rm -rf "$ENV_DIR/bootstrap/$BOOT_STATE" "$ENV_DIR/bootstrap/$BOOT_STATE.backup" "$ENV_DIR/.terraform" \
    "$ENV_DIR/.cluster-mode"
}

cleanup() {
  status=$?
  [ "$status" -eq 0 ] || report_failure
  log "destruyendo el entorno y limpiando (código previo: $status)"
  if ! bash "$ROOT/scripts/down.sh"; then
    log "down.sh falló o se agotó (DESTROY_TIMEOUT=${DESTROY_TIMEOUT}s); diagnóstico y limpieza forzada"
    report_docker
    if only_vpc_left; then
      log "AVISO: solo queda la VPC en el estado (limitación conocida de Floci en Linux); el resto se destruyó"
    else
      log "quedan recursos en el estado, además de la VPC:"
      terraform -chdir="$ENV_DIR" state list 2>&1 || true
      status=1
    fi
    force_cleanup
    bash "$ROOT/scripts/verify-clean.sh" || status=1
  fi
  exit "$status"
}
trap cleanup EXIT

# Una descarga de imagen fallida (ErrImagePull) o un clúster k3s que no arranca dejan el apply en error o colgado; el
# apply está acotado por APPLY_TIMEOUT. Se reintenta una vez desde cero (el estado vive en el Floci descartado).
bash "$ROOT/scripts/up.sh" || {
  log "up.sh falló o se agotó (APPLY_TIMEOUT=${APPLY_TIMEOUT}s); diagnóstico y reintento desde cero"
  report_failure
  report_docker
  docker ps -a --filter 'name=^floci-aws-' --format '{{.Names}}' | while read -r c; do
    log "log de $c:"; docker logs --tail 40 "$c" 2>&1 || true
  done
  force_cleanup
  bash "$ROOT/scripts/up.sh"
}

# La raíz crea una Application por ambiente. Un runner de CI no tiene recursos para que staging y prod (más réplicas,
# HPA) queden Healthy: de esas solo se exige que la raíz las haya creado; la convergencia completa se prueba en local.
log "esperando a Argo CD: Synced + Healthy [${ARGOCD_READY_APPS//,/ }] y creadas [${ARGOCD_PRESENT_APPS//,/ }], máximo ${ARGOCD_TIMEOUT}s"
deadline=$((SECONDS + ARGOCD_TIMEOUT))
while :; do
  pending=()
  for app in ${ARGOCD_READY_APPS//,/ }; do
    state="$(kc get application "$app" -n argocd -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || true)"
    [ "$state" = "Synced/Healthy" ] || pending+=("$app (${state:-ausente})")
  done
  for app in ${ARGOCD_PRESENT_APPS//,/ }; do
    kc get application "$app" -n argocd >/dev/null 2>&1 || pending+=("$app (no creada)")
  done
  if [ "${#pending[@]}" -eq 0 ]; then
    log "Argo CD listo: [${ARGOCD_READY_APPS//,/ }] Synced y Healthy; [${ARGOCD_PRESENT_APPS//,/ }] creadas"
    break
  fi
  if [ "$SECONDS" -ge "$deadline" ]; then
    die "Argo CD no llegó al estado esperado en ${ARGOCD_TIMEOUT}s; pendientes: ${pending[*]}"
  fi
  sleep 10
done
