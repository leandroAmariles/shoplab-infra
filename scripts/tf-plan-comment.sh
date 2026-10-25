#!/usr/bin/env bash
# Arma el cuerpo del comentario del PR con el plan de Terraform: marcador, resumen y plan en un bloque de código,
# truncado a MAX_CHARS. Uso: tf-plan-comment.sh <plan.txt> [<url-de-la-ejecución>] > comment.md
set -euo pipefail

PLAN_FILE="${1:?uso: tf-plan-comment.sh <plan.txt> [<run-url>]}"
RUN_URL="${2:-}"
MAX_CHARS="${MAX_CHARS:-60000}"
MARKER='<!-- shoplab-infra-tf-plan -->'

summary="$(grep -E '^Plan: |^No changes\.' "$PLAN_FILE" | tail -n 1 || true)"
[ -n "$summary" ] || summary="El plan no terminó con un resumen (revisa el log de la ejecución)."

body="$(cat "$PLAN_FILE")"
truncated=""
if [ "${#body}" -gt "$MAX_CHARS" ]; then
  body="${body:0:$MAX_CHARS}"
  truncated="
> El plan se truncó a $MAX_CHARS caracteres."
  [ -z "$RUN_URL" ] || truncated="$truncated Plan completo en la [ejecución]($RUN_URL)."
fi

printf '%s\n### Terraform plan (Floci)\n\n**%s**\n%s\n\n<details><summary>Ver plan</summary>\n\n```text\n%s\n```\n\n</details>\n' \
  "$MARKER" "$summary" "$truncated" "$body"
