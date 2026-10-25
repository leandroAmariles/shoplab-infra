#!/usr/bin/env bash
# Aplica (crea o actualiza) el ruleset de main y los ajustes de fusión del repositorio con gh.
# Ejecutar solo después de que los checks requeridos (ci-gate, pr-title) hayan corrido al menos una vez.
# Uso: apply-ruleset.sh [owner/repo]   (por defecto, el repositorio del directorio actual)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v gh >/dev/null || die "falta gh (GitHub CLI)"
REPO="${1:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
FILE="$ROOT/.github/rulesets/main-protection.json"
NAME="$(sed -nE 's/^[[:space:]]*"name":[[:space:]]*"([^"]+)".*/\1/p' "$FILE" | head -n 1)"

log "ajustes de fusión de $REPO"
gh api -X PATCH "repos/$REPO" \
  -F allow_merge_commit=false -F allow_rebase_merge=false -F allow_squash_merge=true \
  -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=BLANK \
  -F delete_branch_on_merge=true >/dev/null

existing="$(gh api "repos/$REPO/rulesets" --jq ".[] | select(.name==\"$NAME\") | .id" || true)"
if [ -n "$existing" ]; then
  log "actualizando el ruleset '$NAME' ($existing)"
  gh api -X PUT "repos/$REPO/rulesets/$existing" --input "$FILE" >/dev/null
else
  log "creando el ruleset '$NAME'"
  gh api -X POST "repos/$REPO/rulesets" --input "$FILE" >/dev/null
fi
log "listo"
