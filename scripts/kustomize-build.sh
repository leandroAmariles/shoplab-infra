#!/usr/bin/env bash
# Construye cada overlay (dev, staging, prod) con kustomize y valida el resultado con kubeconform. Falla si un overlay
# no existe, rinde 0 recursos o tiene un recurso sin esquema. La salida renderizada queda en RENDER_DIR para las políticas.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# shellcheck disable=SC1091
set -a; source "$ROOT/versions.env"; set +a
command -v kustomize >/dev/null || die "falta kustomize (ver versions.env y scripts/check-tools.sh)"
command -v kubeconform >/dev/null || die "falta kubeconform (ver versions.env y scripts/check-tools.sh)"

RENDER_DIR="${RENDER_DIR:-$ROOT/.rendered}"
rm -rf "$RENDER_DIR"; mkdir -p "$RENDER_DIR"

# Esquemas de Kubernetes más el catálogo comunitario de CRDs (Application de Argo CD, etc.). Un recurso sin esquema
# se rechaza: ignorarlo dejaría pasar manifiestos inválidos en silencio.
CRD_SCHEMAS='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

# Mensaje en el log y, en GitHub Actions, anotación visible en el PR.
fail_msg() { log "$*"; [ "${GITHUB_ACTIONS:-}" != true ] || echo "::error::$*"; }

fail=0
# Por cada ambiente se construye el overlay de cargas de trabajo ($KUSTOMIZE_DIR/<overlay>) y su Application de
# Argo CD ($ARGOCD_DIR/<overlay>); las políticas leen ambos desde RENDER_DIR.
targets=()
for overlay in ${OVERLAYS//,/ }; do
  targets+=("$KUSTOMIZE_DIR/$overlay|$overlay" "$ARGOCD_DIR/$overlay|argocd-$overlay")
done
for target in "${targets[@]}"; do
  rel="${target%%|*}"; name="${target##*|}"
  dir="$ROOT/$rel"
  if [ ! -f "$dir/kustomization.yaml" ]; then
    fail_msg "falta el overlay '$name' ($rel/kustomization.yaml)"
    fail=1; continue
  fi
  out="$RENDER_DIR/$name.yaml"
  if ! kustomize build "$dir" > "$out"; then
    fail_msg "kustomize build falló en '$rel'"
    fail=1; continue
  fi
  resources="$(grep -c '^kind:' "$out" || true)"
  if [ "$resources" -eq 0 ]; then
    fail_msg "'$rel' no rinde ningún recurso"
    fail=1; continue
  fi
  log "kubeconform: $rel ($resources recursos)"
  kubeconform -strict -summary -schema-location default -schema-location "$CRD_SCHEMAS" "$out" || fail=1
done
exit "$fail"
