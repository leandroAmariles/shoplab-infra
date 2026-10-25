#!/usr/bin/env bash
# Ejecuta policy-check.sh sobre cada overlay renderizado por kustomize-build.sh (RENDER_DIR).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

RENDER_DIR="${RENDER_DIR:-$ROOT/.rendered}"
shopt -s nullglob
files=("$RENDER_DIR"/*.yaml)
[ "${#files[@]}" -gt 0 ] || die "no hay overlays renderizados en $RENDER_DIR (ejecuta scripts/kustomize-build.sh)"

fail=0
for f in "${files[@]}"; do
  bash "$ROOT/scripts/policy-check.sh" "$f" || fail=1
done
exit "$fail"
