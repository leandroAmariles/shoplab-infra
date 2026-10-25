#!/usr/bin/env bash
# Data source "external": devuelve la IP de Floci en la red de compose. Los pods de k3s no resuelven nombres de
# contenedor ni host.docker.internal, pero sí alcanzan esa IP porque el contenedor de k3s está en la misma red.
set -euo pipefail
export MSYS_NO_PATHCONV=1

network="${FLOCI_NETWORK:-shoplab-infra_default}"
ip="$(docker inspect shoplab-floci --format "{{(index .NetworkSettings.Networks \"$network\").IPAddress}}" 2>/dev/null || true)"
[ -n "$ip" ] || { echo "no se pudo obtener la IP de shoplab-floci en la red $network" >&2; exit 1; }
printf '{"ip":"%s"}\n' "$ip"
