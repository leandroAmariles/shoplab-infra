#!/usr/bin/env bash
# Apaga el entorno sin borrar nada: cierra los túneles y detiene Floci y los contenedores que crea (k3s y registro). Los
# volúmenes (estado de Terraform, secretos, clúster y PVC) se conservan y `make up` lo reanuda. Para borrarlo todo:
# `make destroy`.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

bash "$ROOT/scripts/forward.sh" stop

# Floci detiene al apagarse los k3s que creó: se le da tiempo antes de forzar la parada.
log "deteniendo Floci"
docker compose -f "$ROOT/docker-compose.yml" stop -t 60

docker ps -q --filter 'name=^floci-aws-' --filter "name=^shoplab-$ENV_NAME-control-plane$" \
  | xargs -r docker stop >/dev/null

log "entorno detenido; make up lo reanuda"
