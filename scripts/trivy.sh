#!/usr/bin/env bash
# Trivy config sobre el código de infraestructura: falla ante hallazgos HIGH/CRITICAL no exceptuados en .trivyignore.
# En CI el informe SARIF y la compuerta los ejecuta trivy-action con los mismos parámetros.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v trivy >/dev/null || die "falta trivy (ver versions.env y scripts/check-tools.sh)"
cd "$ROOT"
log "trivy config terraform/"
trivy config --severity HIGH,CRITICAL --ignorefile .trivyignore --exit-code 1 --skip-dirs '**/.terraform' terraform

# Manifiestos: se analiza la salida renderizada de cada overlay (scripts/kustomize-build.sh), no los archivos sueltos.
RENDER_DIR="${RENDER_DIR:-$ROOT/.rendered}"
[ -d "$RENDER_DIR" ] || die "no hay overlays renderizados en $RENDER_DIR (ejecuta scripts/kustomize-build.sh)"
log "trivy config ${RENDER_DIR#"$ROOT"/}"
trivy config --severity HIGH,CRITICAL --ignorefile .trivyignore --exit-code 1 "$RENDER_DIR"
