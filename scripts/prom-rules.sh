#!/usr/bin/env bash
# Valida y prueba las reglas de alerta del backend (LAB-102). Extrae la PrometheusRule del overlay dev ya renderizado
# por scripts/kustomize-build.sh (RENDER_DIR), la comprueba con `promtool check rules` y ejecuta las pruebas de
# rules-tests/*.test.yaml con `promtool test rules`. Falla si el overlay no contiene ninguna PrometheusRule.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# shellcheck disable=SC1091
set -a; source "$ROOT/versions.env"; set +a
command -v promtool >/dev/null || die "falta promtool (ver versions.env y scripts/check-tools.sh)"
command -v yq >/dev/null || die "falta yq (ver versions.env y scripts/check-tools.sh)"

RENDER_DIR="${RENDER_DIR:-$ROOT/.rendered}"
rendered="$RENDER_DIR/dev.yaml"
[ -f "$rendered" ] || die "no existe $rendered (ejecuta scripts/kustomize-build.sh)"

shopt -s nullglob
tests=("$ROOT"/rules-tests/*.test.yaml)
[ "${#tests[@]}" -gt 0 ] || die "no hay pruebas de reglas en rules-tests/"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
yq eval --no-doc 'select(.kind == "PrometheusRule") | .spec' "$rendered" > "$tmp/rules.yaml"
[ -s "$tmp/rules.yaml" ] || die "el overlay dev no contiene ninguna PrometheusRule"

# promtool resuelve rule_files respecto al archivo de prueba: se copian juntos y se ejecuta dentro de $tmp, con rutas
# relativas, para no depender de cómo representa las rutas temporales el sistema (Git Bash en Windows).
cp "${tests[@]}" "$tmp/"
log "promtool check rules"
(cd "$tmp" && promtool check rules rules.yaml)
for t in "${tests[@]}"; do
  log "promtool test rules: $(basename "$t")"
  (cd "$tmp" && promtool test rules "$(basename "$t")")
done
