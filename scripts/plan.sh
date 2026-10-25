#!/usr/bin/env bash
# terraform plan contra un Floci efímero: levanta Floci, crea el bucket de estado, planifica y baja Floci al terminar.
# El estado es nuevo en cada ejecución, así que el plan siempre muestra la creación completa. Salida en $PLAN_OUT.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v docker >/dev/null || die "Docker no está instalado"
command -v terraform >/dev/null || die "Terraform no está instalado"

# shellcheck disable=SC1091
set -a; source "$ROOT/versions.env"; set +a
export EMULATOR_URL
PLAN_OUT="${PLAN_OUT:-$ROOT/plan.txt}"
CLUSTER_MODE="${CLUSTER_MODE:-floci}"

# Solo se planifica: si no hay valores de secretos, valen marcadores obvios.
if [ ! -f "$ENV_DIR/secrets.auto.tfvars" ] && [ -z "${TF_VAR_secrets:-}" ]; then
  export TF_VAR_secrets='{"postgres-password"="CHANGE_ME","llm-api-key"="CHANGE_ME"}'
fi

if ! docker ps --format '{{.Names}}' | grep -qx shoplab-floci && curl -fsS "$EMULATOR_URL/_localstack/health" >/dev/null 2>&1; then
  die "El puerto 4566 ya lo usa otro emulador; deténlo o cambia EMULATOR_URL"
fi

cleanup() {
  log "apagando Floci"
  docker compose -f "$ROOT/docker-compose.yml" down --remove-orphans >/dev/null 2>&1 || true
  docker ps -aq --filter 'name=^floci-aws-' | xargs -r docker rm -f >/dev/null 2>&1 || true
  docker network ls --format '{{.Name}}' | grep -E '^(floci-aws-|shoplab-infra_default$)' | xargs -r docker network rm >/dev/null 2>&1 || true
  rm -rf "$ENV_DIR/bootstrap/$BOOT_STATE" "$ENV_DIR/bootstrap/$BOOT_STATE.backup"
}
trap cleanup EXIT

log "levantando Floci (${FLOCI_IMAGE}), espera máxima ${FLOCI_READY_TIMEOUT}s"
docker compose -f "$ROOT/docker-compose.yml" up -d
tries=$((FLOCI_READY_TIMEOUT / 2))
until curl -fsS "$EMULATOR_URL/_localstack/health" >/dev/null 2>&1; do
  tries=$((tries - 1))
  [ "$tries" -gt 0 ] || die "Floci no respondió en ${FLOCI_READY_TIMEOUT}s en $EMULATOR_URL"
  sleep 2
done

bash "$ROOT/scripts/bootstrap.sh"
bash "$ROOT/scripts/init-env.sh"

log "terraform plan ($ENV_NAME)"
set +e
terraform -chdir="$ENV_DIR" plan -input=false -no-color \
  -var "environment=$ENV_NAME" -var "emulator_endpoint=$EMULATOR_URL" -var "cluster_mode=$CLUSTER_MODE" \
  2>&1 | tee "$PLAN_OUT"
status="${PIPESTATUS[0]}"
set -e
exit "$status"
