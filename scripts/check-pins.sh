#!/usr/bin/env bash
# Falla ante versiones flotantes: `latest`, imágenes sin tag, o providers/charts con rangos en lugar de X.Y.Z (FR-011).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fail=0

# 1) providers y charts: cada `version = "..."` debe ser exacta (required_version admite ~> X.Y.Z y no se evalúa aquí).
while IFS= read -r hit; do
  value="$(printf '%s' "$hit" | sed -E 's/.*version[[:space:]]*=[[:space:]]*"([^"]*)".*/\1/')"
  if ! printf '%s' "$value" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    log "versión no fija ($value): $hit"
    fail=1
  fi
done < <(grep -rEn --include='*.tf' '^[[:space:]]*version[[:space:]]*=[[:space:]]*"' "$ROOT/terraform" | grep -v required_version | sed "s#$ROOT/##")

# 2) `latest` en código Terraform y compose (se ignoran comentarios).
if grep -rEn --include='*.tf' --include='docker-compose*.yml' ':latest|"latest"' "$ROOT/terraform" "$ROOT/docker-compose.yml" \
  | sed "s#$ROOT/##" | grep -Ev '^[^:]+:[0-9]+:[[:space:]]*(#|//)' | grep .; then
  log "se encontró 'latest' en el código"
  fail=1
fi

# 3) imágenes de compose con tag explícito.
while IFS= read -r image; do
  case "$image" in
    *:*) ;;
    *) log "imagen sin tag en docker-compose.yml: $image"; fail=1 ;;
  esac
done < <(sed -nE 's/^[[:space:]]*image:[[:space:]]*(.*)$/\1/p' "$ROOT/docker-compose.yml")

# 4) k3s de Floci: debe indicarse una imagen con tag fijo.
grep -Eq 'FLOCI_SERVICES_EKS_DEFAULT_IMAGE:[[:space:]]*[^[:space:]]+:v?[0-9]' "$ROOT/docker-compose.yml" \
  || { log "FLOCI_SERVICES_EKS_DEFAULT_IMAGE debe fijarse a un tag de versión"; fail=1; }

[ "$fail" -eq 0 ] && log "todas las versiones están fijadas"
exit "$fail"
