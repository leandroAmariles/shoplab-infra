#!/usr/bin/env bash
# Mide la calidad de las respuestas del asistente del clúster de dev (LAB-29): ejecuta `python -m shoplab_eval quality` de
# shoplab-helpdesk contra el ingress, con el gateway LiteLLM como juez y Langfuse para adjuntar las puntuaciones.
# Las claves salen de los Secrets del clúster y viajan por variables de entorno del proceso: no se imprimen ni van en argumentos.
# Requiere `make up` + `make seed` + `make forward` (los túneles de LiteLLM 4000 y Langfuse 3001) y el juez en Ollama.
# Los argumentos se pasan tal cual al comando (p. ej. `make quality ARGS="--run-id demo-1 --no-langfuse"`).
# Con el Secret backend-eval (LAB-31) la ejecución también se guarda en el historial del backend; `ARGS="--no-save"` lo evita.
#   HELPDESK_DIR   shoplab-helpdesk (por defecto ../shoplab-helpdesk)
#   INGRESS_PORT   puerto del ingress en el host (por defecto 8080)
#   NAMESPACE      namespace de la app (por defecto shoplab-dev)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

HELPDESK_DIR="${HELPDESK_DIR:-$ROOT/../shoplab-helpdesk}"
INGRESS_PORT="${INGRESS_PORT:-8080}"
NAMESPACE="${NAMESPACE:-shoplab-dev}"
KUBECONFIG_FILE="$ENV_DIR/kubeconfig.yaml"

[ -d "$HELPDESK_DIR/eval" ] || die "no existe $HELPDESK_DIR/eval (define HELPDESK_DIR con la ruta de shoplab-helpdesk)"
command -v uv >/dev/null || die "uv no está instalado (lo usa eval/ de shoplab-helpdesk)"
command -v kubectl >/dev/null || die "kubectl no está instalado"
[ -f "$KUBECONFIG_FILE" ] || die "no existe $KUBECONFIG_FILE: ejecuta make up primero"

# Se comprueba antes de leer secretos o de gastar tiempo: los túneles los deja make forward (y make up).
http_code() { curl -s -m 5 -o /dev/null -w '%{http_code}' "$@" 2>/dev/null || true; }
[ "$(http_code -H 'Host: shoplab.localtest.me' "http://127.0.0.1:$INGRESS_PORT/api/documents")" = 200 ] \
  || die "el backend no responde en el ingress (127.0.0.1:$INGRESS_PORT): ¿make up, make forward y make seed?"
code="$(http_code http://127.0.0.1:4000/health/liveliness)"
{ [ -n "$code" ] && [ "$code" != 000 ]; } || die "LiteLLM no responde en localhost:4000: ejecuta make forward"
code="$(http_code http://127.0.0.1:3001/api/public/health)"
{ [ -n "$code" ] && [ "$code" != 000 ]; } || die "Langfuse no responde en localhost:3001: ejecuta make forward"

secret_value() { # secreto clave -> valor (sin salto de línea)
  kubectl --kubeconfig "$KUBECONFIG_FILE" -n "$NAMESPACE" get secret "$1" -o "jsonpath={.data.$2}" 2>/dev/null \
    | base64 -d | tr -d '\r\n'
}
judge_key="$(secret_value litellm-credentials LITELLM_KEY_EVAL)"
[ -n "$judge_key" ] || die "el Secret litellm-credentials no tiene LITELLM_KEY_EVAL: ejecuta make secrets y reaplica (make up); el Job litellm-bootstrap-keys crea la clave"
lf_public="$(secret_value langfuse-credentials LANGFUSE_INIT_PROJECT_PUBLIC_KEY)"
lf_secret="$(secret_value langfuse-credentials LANGFUSE_INIT_PROJECT_SECRET_KEY)"
[ -n "$lf_public" ] && [ -n "$lf_secret" ] || die "el Secret langfuse-credentials no tiene las claves del proyecto de Langfuse"

# Historial de evaluación (LAB-31): el token con el que `eval/` guarda la ejecución en el backend. Es opcional.
eval_token="$(secret_value backend-eval SHOPLAB_EVAL_PERSISTENCE_TOKEN || true)"

# El backend no expone qué modelo corre: se registra el que fijó el despliegue (parámetro llm-model del tfvars).
assistant_model="${SHOPLAB_EVAL_ASSISTANT_MODEL:-}"
if [ -z "$assistant_model" ] && [ -f "$ENV_DIR/secrets.auto.tfvars" ]; then
  assistant_model="$(sed -n 's/^[[:space:]]*llm-model[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "$ENV_DIR/secrets.auto.tfvars" | tr -d '\r' | head -1)"
fi

export SHOPLAB_EVAL_BASE_URL="http://127.0.0.1:$INGRESS_PORT"
export SHOPLAB_EVAL_HOST_HEADER="shoplab.localtest.me"
export SHOPLAB_EVAL_JUDGE_BASE_URL="http://localhost:4000/v1"
export SHOPLAB_EVAL_JUDGE_API_KEY="$judge_key"
export SHOPLAB_EVAL_LANGFUSE_HOST="http://localhost:3001"
export SHOPLAB_EVAL_LANGFUSE_PUBLIC_KEY="$lf_public"
export SHOPLAB_EVAL_LANGFUSE_SECRET_KEY="$lf_secret"
[ -z "$assistant_model" ] || export SHOPLAB_EVAL_ASSISTANT_MODEL="$assistant_model"
if [ -n "$eval_token" ]; then
  export SHOPLAB_EVAL_TOKEN="$eval_token"
  export SHOPLAB_EVAL_ORIGIN="${SHOPLAB_EVAL_ORIGIN:-dev}"
  log "la ejecución se guardará en el historial de evaluación del backend (ARGS=\"--no-save\" lo evita)"
else
  log "aviso: el Secret backend-eval no existe o está vacío (¿make secrets y make up?): se mide sin guardar la ejecución en el historial"
fi

log "midiendo la calidad de las respuestas contra $SHOPLAB_EVAL_BASE_URL (Host shoplab.localtest.me)"
cd "$HELPDESK_DIR/eval"
uv run python -m shoplab_eval quality "$@"
