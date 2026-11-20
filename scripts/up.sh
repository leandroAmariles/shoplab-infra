#!/usr/bin/env bash
# De cero a Argo CD: Floci -> bootstrap del estado -> terraform apply. Se puede reanudar tras una interrupción.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v docker >/dev/null || die "Docker no está instalado"
command -v terraform >/dev/null || die "Terraform no está instalado"

# Los valores de secretos vienen de fuera del repositorio: se avisa antes de levantar nada.
if [ ! -f "$ENV_DIR/secrets.auto.tfvars" ] && [ -z "${TF_VAR_secrets:-}" ]; then
  die "faltan los valores de secretos: copia $ENV_DIR/secrets.auto.tfvars.example como secrets.auto.tfvars y complétalo (o define TF_VAR_secrets)"
fi
# Completa lo que falte (langfuse, litellm y la clave `eval` de LAB-29) sin tocar lo que ya hay: sin ellas el Job
# litellm-bootstrap-keys aborta y el gateway no queda con claves. Si no se puede completar, no se levanta nada a medias.
bash "$ROOT/scripts/ensure-secrets.sh"
# Ollama corre en el host (Docker), fuera del clúster: solo avisa si le faltan modelos.
bash "$ROOT/scripts/check-host-ollama.sh"

# Puerto 4566 ocupado por algo que no es nuestro Floci.
if ! docker ps --format '{{.Names}}' | grep -qx shoplab-floci; then
  if curl -fsS "$EMULATOR_URL/_localstack/health" >/dev/null 2>&1; then
    die "El puerto 4566 ya lo usa otro emulador; deténlo o cambia EMULATOR_URL"
  fi
fi

# down.sh necesita el mismo modo para poder destruir (floci o kind).
CLUSTER_MODE="${CLUSTER_MODE:-floci}"
printf '%s\n' "$CLUSTER_MODE" > "$ENV_DIR/.cluster-mode"

log "levantando Floci"
docker compose -f "$ROOT/docker-compose.yml" up -d
wait_for_emulator

bash "$ROOT/scripts/bootstrap.sh"
bash "$ROOT/scripts/init-env.sh"

log "aplicando el entorno $ENV_NAME"
# APPLY_TIMEOUT (segundos) acota el apply: lo usa la prueba de humo para no colgarse si el emulador no levanta el clúster.
apply_timeout=()
[ -z "${APPLY_TIMEOUT:-}" ] || apply_timeout=(timeout -k 30 "$APPLY_TIMEOUT")
"${apply_timeout[@]}" terraform -chdir="$ENV_DIR" apply -input=false -auto-approve \
  -var "environment=$ENV_NAME" -var "emulator_endpoint=$EMULATOR_URL" \
  -var "cluster_mode=$CLUSTER_MODE"

# Terraform termina cuando Argo CD está instalado, no cuando ha sincronizado la app: el namespace y los pods de LiteLLM y
# Langfuse aparecen minutos después. Si forward.sh corre antes, esos dos túneles salen en FALLO. Se espera (acotado por
# WAIT_APPS_TIMEOUT, 600 s por defecto) y, si no llegan a tiempo, solo se avisa: make forward los relanza.
#   APP_NAMESPACE   namespace de la app (por defecto shoplab-dev, el mismo que usa forward.sh)
wait_for_apps() {
  local ns="${APP_NAMESPACE:-shoplab-dev}" deadline kc
  command -v kubectl >/dev/null && [ -f "$ENV_DIR/kubeconfig.yaml" ] || return 0
  kc=(kubectl --kubeconfig "$ENV_DIR/kubeconfig.yaml")
  deadline=$((SECONDS + ${WAIT_APPS_TIMEOUT:-600}))
  log "esperando a que Argo CD despliegue litellm y langfuse-web en $ns (hasta ${WAIT_APPS_TIMEOUT:-600} s)"
  until "${kc[@]}" -n "$ns" get deploy/litellm deploy/langfuse-web >/dev/null 2>&1; do
    [ "$SECONDS" -lt "$deadline" ] || { log "AVISO: litellm y langfuse-web aún no existen en $ns; sus túneles pueden fallar, relánzalos con make forward"; return 0; }
    sleep 5
  done
  "${kc[@]}" -n "$ns" wait --for=condition=Available deploy/litellm deploy/langfuse-web --timeout="$((deadline - SECONDS > 1 ? deadline - SECONDS : 1))s" >/dev/null 2>&1 \
    || log "AVISO: litellm y langfuse-web no quedaron disponibles a tiempo; sus túneles pueden fallar, relánzalos con make forward"
}
wait_for_apps

# Sin kubectl o con el puerto ocupado no se falla: el entorno ya está arriba y se puede reintentar con make forward.
bash "$ROOT/scripts/forward.sh" || log "AVISO: el ingress no quedó expuesto; resuélvelo y ejecuta make forward"

log "listo. kubectl --kubeconfig $ENV_DIR/kubeconfig.yaml get pods -A"
