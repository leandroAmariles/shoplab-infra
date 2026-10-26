#!/usr/bin/env bash
# Construye el overlay dev con kustomize y valida el resultado con kubeconform. Falla si un overlay
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
# Se construye cada overlay de cargas de trabajo ($KUSTOMIZE_DIR/<overlay>) y, una sola vez, el directorio de las
# Application de Argo CD ($ARGOCD_DIR, la del ambiente dev); las políticas leen todo desde RENDER_DIR.
targets=()
for overlay in ${OVERLAYS//,/ }; do
  targets+=("$KUSTOMIZE_DIR/$overlay|$overlay")
done
targets+=("$ARGOCD_DIR|argocd")
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

# La Application raíz (root.yaml) vive junto a la de dev pero no entra en el kustomization: la crea Terraform y no
# se gestiona a sí misma. Se valida aparte; si aparece también en la salida de $ARGOCD_DIR hay un bucle de autogestión.
root="$ROOT/$ARGOCD_DIR/root.yaml"
if [ ! -f "$root" ]; then
  fail_msg "falta la Application raíz de Argo CD ($ARGOCD_DIR/root.yaml)"
  fail=1
else
  cp "$root" "$RENDER_DIR/argocd-root.yaml"
  root_name="$(yq eval '.metadata.name' "$root")"
  if [ -f "$RENDER_DIR/argocd.yaml" ] \
    && [ -n "$(yq eval --no-doc "select(.kind == \"Application\" and .metadata.name == \"$root_name\") | .metadata.name" \
      "$RENDER_DIR/argocd.yaml")" ]; then
    fail_msg "la salida de 'argocd' incluye la Application raíz '$root_name': quítala (se gestionaría a sí misma)"
    fail=1
  fi
  # La raíz debe sincronizar el directorio que este script construye (si no, apuntaría a algo sin validar o inexistente).
  root_path="$(yq eval '.spec.source.path' "$root")"
  if [ "$root_path" != "$ARGOCD_DIR" ]; then
    fail_msg "root.yaml sincroniza '$root_path', que no es '$ARGOCD_DIR'"
    fail=1
  fi
  log "kubeconform: $ARGOCD_DIR/root.yaml"
  kubeconform -strict -summary -schema-location default -schema-location "$CRD_SCHEMAS" "$RENDER_DIR/argocd-root.yaml" \
    || fail=1
fi
exit "$fail"
