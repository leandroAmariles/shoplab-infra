#!/usr/bin/env bash
# De cero a Argo CD: Floci -> bootstrap del estado -> terraform apply. Se puede reanudar tras una interrupción.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v docker >/dev/null || die "Docker no está instalado"
command -v terraform >/dev/null || die "Terraform no está instalado"

# Puerto 4566 ocupado por algo que no es nuestro Floci.
if ! docker ps --format '{{.Names}}' | grep -qx shoplab-floci; then
  if curl -fsS "$EMULATOR_URL/_localstack/health" >/dev/null 2>&1; then
    die "El puerto 4566 ya lo usa otro emulador; deténlo o cambia EMULATOR_URL"
  fi
fi

log "levantando Floci"
docker compose -f "$ROOT/docker-compose.yml" up -d
wait_for_emulator

bash "$ROOT/scripts/bootstrap.sh"
bash "$ROOT/scripts/init-env.sh"

log "aplicando el entorno $ENV_NAME"
terraform -chdir="$ENV_DIR" apply -input=false -auto-approve \
  -var "environment=$ENV_NAME" -var "emulator_endpoint=$EMULATOR_URL" \
  -var "cluster_mode=${CLUSTER_MODE:-floci}"

log "listo. kubectl --kubeconfig $ENV_DIR/kubeconfig.yaml get pods -A"
