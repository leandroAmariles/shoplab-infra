#!/usr/bin/env bash
# Políticas sobre manifiestos ya renderizados (salida de `kustomize build`). Reglas: contracts/policy-rules.md de LAB-99.
#   IMAGE_LATEST | IMAGE_NO_TAG | TEMPLATE_REPO_URL | TARGET_REVISION_NOT_MAIN | PLAIN_SECRET (LAB-80)
#   | APPLICATION_NO_FINALIZER (LAB-79)
# Uso: policy-check.sh <rendered.yaml> [<overlay>]. Salida: 0 sin violaciones, 1 con alguna, 2 por error de uso o de lectura.
set -uo pipefail

file="${1:-}"
overlay="${2:-$(basename "${file:-?}" .yaml)}"
[ -n "$file" ] && [ -r "$file" ] || { echo "uso: policy-check.sh <rendered.yaml> [<overlay>]" >&2; exit 2; }
command -v yq >/dev/null || { echo "falta yq (ver versions.env y scripts/check-tools.sh)" >&2; exit 2; }

violations=0
report() { # regla recurso valor
  violations=$((violations + 1))
  printf '%s | %s | %s | %s\n' "$1" "$overlay" "$2" "$3" >&2
  [ "${GITHUB_ACTIONS:-}" != true ] || printf '::error title=%s::%s | %s | %s\n' "$1" "$overlay" "$2" "$3"
}

# Identificador legible del recurso de cada documento: Kind/namespace/nombre.
ID='(.kind + "/" + (.metadata.namespace // "-") + "/" + (.metadata.name // "-"))'

# Imágenes de containers, initContainers y ephemeralContainers de cualquier workload o plantilla de pod.
images="$(yq eval --no-doc "select(.kind != null) | $ID as \$id |
  .. | select(tag == \"!!map\") | (.containers, .initContainers, .ephemeralContainers) | select(. != null) | .[] |
  select(.image != null) | \$id + \"\t\" + .image" "$file")" || { echo "no se pudo leer $file" >&2; exit 2; }

while IFS=$'\t' read -r id image; do
  [ -n "$image" ] || continue
  name="${image%%@*}"                        # sin digest
  tag=""
  case "${name##*/}" in *:*) tag="${name##*:}" ;; esac   # el tag va tras el último ':' si este sigue al último '/'
  if [ "$tag" = latest ]; then
    report IMAGE_LATEST "$id" "image=$image"
  elif [ -z "$tag" ] && [ "$name" = "$image" ]; then
    report IMAGE_NO_TAG "$id" "image=$image"
  fi
done <<< "$images"

# targetRevision de Application (spec) y ApplicationSet (spec.template.spec); ausente = <unset>.
revisions="$(yq eval --no-doc "select(.kind == \"Application\" or .kind == \"ApplicationSet\") | $ID as \$id |
  (.spec.template.spec // .spec) as \$s | (([\$s.source] | map(select(. != null))) + (\$s.sources // []))[] |
  \$id + \"	\" + (.targetRevision // \"<unset>\")" "$file")" \
  || { echo "no se pudo leer $file" >&2; exit 2; }

while IFS=$'\t' read -r id revision; do
  [ -n "$id" ] || continue
  [ "$revision" = main ] || report TARGET_REVISION_NOT_MAIN "$id" "targetRevision=$revision"
done <<< "$revisions"

# Toda Application lleva el finalizer de Argo CD: sin él, quitarla de git deja sus recursos huérfanos en el clúster.
finalizers="$(yq eval --no-doc "select(.kind == \"Application\") | $ID as \$id |
  \$id + \"	\" + ((.metadata.finalizers // []) | contains([\"resources-finalizer.argocd.argoproj.io\"]) | tostring)" "$file")" \
  || { echo "no se pudo leer $file" >&2; exit 2; }

while IFS=$'\t' read -r id has_finalizer; do
  [ -n "$id" ] || continue
  [ "$has_finalizer" = true ] || report APPLICATION_NO_FINALIZER "$id" "falta resources-finalizer.argocd.argoproj.io"
done <<< "$finalizers"

# Ningún recurso Secret en la salida: las credenciales se declaran como ExternalSecret y nunca viven en git.
secrets="$(yq eval --no-doc "select(.kind == \"Secret\") | $ID" "$file")" \
  || { echo "no se pudo leer $file" >&2; exit 2; }
while IFS= read -r id; do
  [ -n "$id" ] && report PLAIN_SECRET "$id" "kind Secret found (use ExternalSecret)"
done <<< "$secrets"

# El placeholder de la plantilla debe haberse reemplazado en todo el texto.
while IFS= read -r line; do
  [ -n "$line" ] && report TEMPLATE_REPO_URL "${line%%:*}" "${line#*:}"
done < <(grep -n 'CAMBIA-ESTE-OWNER' "$file" | sed -E 's/^([0-9]+):[[:space:]]*/línea \1:/')

if [ "$violations" -gt 0 ]; then
  echo "policy-check: $violations violation(s) in overlay $overlay"
  exit 1
fi
echo "policy-check: ok ($overlay)"
