#!/usr/bin/env bash
# Falla si queda algo del entorno: contenedores de Floci o creados por Floci fuera de compose, y sus redes.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

leftovers="$(docker ps -a --format '{{.Names}}' | grep -E "^(shoplab-floci|floci-aws-|shoplab-$ENV_NAME-control-plane)" || true)"
networks="$(docker network ls --format '{{.Name}}' | grep -E '^(floci-aws-|shoplab-infra_)' || true)"

if [ -n "$leftovers$networks" ]; then
  log "quedan recursos del entorno:"
  printf '%s\n%s\n' "$leftovers" "$networks" | sed '/^$/d' >&2
  exit 1
fi
log "entorno limpio"
