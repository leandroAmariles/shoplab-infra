#!/usr/bin/env bash
# Borra todo: terraform destroy del entorno, destroy del bootstrap y limpieza de Floci. Se puede reintentar.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

use_placeholder_secrets_if_missing # terraform destroy exige la variable aunque no use sus valores

# Se destruye con el mismo modo con el que se levantó (lo recuerda up.sh); CLUSTER_MODE lo sobrescribe.
if [ -z "${CLUSTER_MODE:-}" ] && [ -f "$ENV_DIR/.cluster-mode" ]; then
  CLUSTER_MODE="$(tr -d '\r\n' < "$ENV_DIR/.cluster-mode")"
fi
CLUSTER_MODE="${CLUSTER_MODE:-floci}"

if curl -fsS "$EMULATOR_URL/_localstack/health" >/dev/null 2>&1; then
  # Sin bucket de estado no hay nada desplegado (p. ej. un down repetido): se omite el destroy del entorno.
  if [ -d "$ENV_DIR/.terraform" ] \
    && curl -sI "$EMULATOR_URL/shoplab-tfstate-$ENV_NAME" | head -n 1 | grep -q ' 200'; then
    log "destruyendo el entorno $ENV_NAME (modo $CLUSTER_MODE)"
    bash "$ROOT/scripts/init-env.sh"
    terraform -chdir="$ENV_DIR" destroy -input=false -auto-approve \
      -var "environment=$ENV_NAME" -var "emulator_endpoint=$EMULATOR_URL" \
      -var "cluster_mode=$CLUSTER_MODE"
  fi
  if [ -d "$ENV_DIR/bootstrap/.terraform" ]; then
    log "destruyendo el bucket de estado"
    terraform -chdir="$ENV_DIR/bootstrap" destroy -input=false -auto-approve -state="$BOOT_STATE" \
      -var "environment=$ENV_NAME" -var "emulator_endpoint=$EMULATOR_URL"
  fi
else
  log "Floci no responde: se omite terraform destroy y se limpian solo los contenedores"
fi

log "apagando Floci"
docker compose -f "$ROOT/docker-compose.yml" down --remove-orphans

# Floci crea contenedores y redes fuera de compose (registro ECR, k3s, VPC): docker compose down no los borra.
docker ps -aq --filter 'name=^floci-aws-' | xargs -r docker rm -f >/dev/null
docker network ls --format '{{.Name}}' | grep -E '^(floci-aws-|shoplab-infra_default$)' | xargs -r docker network rm >/dev/null || true

# Clúster de kind del modo de respaldo, si algo impidió que terraform destroy lo eliminara.
docker ps -aq --filter "name=^shoplab-$ENV_NAME-control-plane$" | xargs -r docker rm -f >/dev/null

# Estado local desechable del bootstrap y artefactos generados.
rm -rf "$ENV_DIR/bootstrap/$BOOT_STATE" "$ENV_DIR/bootstrap/$BOOT_STATE.backup" "$ENV_DIR/kubeconfig.yaml" \
  "$ENV_DIR/.cluster-mode"

bash "$ROOT/scripts/verify-clean.sh"
