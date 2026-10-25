#!/usr/bin/env bash
# TFLint recursivo sobre terraform/ con .tflint.hcl (plugin AWS fijado en versions.env).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

command -v tflint >/dev/null || die "falta tflint (ver versions.env y scripts/check-tools.sh)"
cd "$ROOT"
log "tflint --init"
tflint --init --config "$ROOT/.tflint.hcl"
log "tflint --recursive"
tflint --recursive --config "$ROOT/.tflint.hcl" --chdir "$ROOT/terraform"
