#!/usr/bin/env bash
# Dice si un push solo cambia los tags de imagen del overlay dev: el commit automático de despliegue de LAB-81
# (`chore(dev): [LAB-81] despliega <sha> a dev`), que el CI no necesita probar con un apply completo (smoke).
# Uso: is-dev-deploy-only.sh <commit-anterior> <commit-nuevo>   (se ejecuta dentro del repositorio)
# Salida: 0 = el único archivo cambiado es el overlay y solo cambian líneas `newTag: <sha de 40 hex>`;
#         1 = cualquier otro cambio, o no se puede saber (rama nueva, commit ausente): ante la duda, se prueba todo.
set -euo pipefail

FILE="k8s/overlays/dev/kustomization.yaml"
before="${1:-}"; after="${2:-}"

[ -n "$before" ] && [ -n "$after" ] || exit 1
case "$before" in *[!0]*) ;; *) exit 1 ;; esac # todo ceros: el push crea la rama
git cat-file -e "$before^{commit}" 2>/dev/null || exit 1
git cat-file -e "$after^{commit}" 2>/dev/null || exit 1

[ "$(git diff --name-only "$before" "$after")" = "$FILE" ] || exit 1

# Toda línea añadida o eliminada debe ser un newTag con un sha completo; cualquier otra (namespace, patches, etc.) obliga a probar.
other="$(git diff -U0 "$before" "$after" -- "$FILE" | grep -E '^[+-]' | grep -vE '^(\+\+\+|---) ' \
  | grep -vE '^[+-][[:space:]]+newTag: [0-9a-f]{40}[[:space:]]*$' || true)"
[ -z "$other" ]
