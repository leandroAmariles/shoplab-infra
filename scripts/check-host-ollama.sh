#!/usr/bin/env bash
# Avisa (nunca falla) si el Ollama del host (Docker, fuera del clúster por su peso) no responde o le faltan modelos.
# El clúster de dev lo consume a través de LiteLLM: sin `llama3.2:3b` y `bge-m3` el chat y la ingesta no funcionan, y sin el
# juez (`qwen2.5:7b`) solo falla `make quality` (LAB-29).
#   OLLAMA_URL         dónde responde Ollama (por defecto http://localhost:11434)
#   OLLAMA_MODELS      modelos que necesita la app (por defecto: llama3.2:3b bge-m3)
#   OLLAMA_JUDGE_MODEL modelo del juez de calidad (por defecto: qwen2.5:7b)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
OLLAMA_MODELS="${OLLAMA_MODELS:-llama3.2:3b bge-m3}"
OLLAMA_JUDGE_MODEL="${OLLAMA_JUDGE_MODEL:-qwen2.5:7b}"

tags="$(curl -fsS -m 5 "$OLLAMA_URL/api/tags" 2>/dev/null || true)"
if [ -z "$tags" ]; then
  # Desde LAB-84 el Ollama de shoplab-helpdesk NO publica puerto: el clúster solo lo alcanza (por 172.17.0.1:11434, ver
  # k8s/overlays/dev/ollama-host.yaml) si se levantó con el override que lo publica. Es el fallo más probable tras make up.
  if command -v docker >/dev/null 2>&1 && docker ps --format '{{.Names}}' 2>/dev/null | grep -q ollama; then
    log "AVISO: Ollama corre pero no publica el puerto 11434, así que el clúster no lo alcanza (sin chat ni embeddings). En shoplab-helpdesk: docker compose -f infra/docker-compose.yml -f infra/docker-compose.ollama-host.yml [-f infra/docker-compose.gpu.yml] up -d ollama"
  else
    log "AVISO: no responde Ollama en $OLLAMA_URL; en dev corre en el Docker del host (shoplab-helpdesk, ver k8s/overlays/dev/ollama-host.yaml). Sin él no hay chat ni embeddings"
  fi
  exit 0
fi

missing=""
for model in $OLLAMA_MODELS; do
  case "$tags" in *"\"name\":\"$model\""*) ;; *) missing="$missing $model" ;; esac
done
[ -z "$missing" ] || log "AVISO: a Ollama le faltan modelos de la app:$missing (descárgalos con ollama pull o con OLLAMA_*_MODEL en shoplab-helpdesk/infra/.env)"
case "$tags" in
  *"\"name\":\"$OLLAMA_JUDGE_MODEL\""*) ;;
  *) log "AVISO: falta el modelo del juez $OLLAMA_JUDGE_MODEL: solo lo necesita make quality (OLLAMA_JUDGE_MODEL=$OLLAMA_JUDGE_MODEL en shoplab-helpdesk/infra/.env, o ollama pull)" ;;
esac
exit 0
