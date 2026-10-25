#!/usr/bin/env bash
# Prueba de integración: aplica el ambiente completo contra Floci (ambiente "itest") y lo destruye al terminar.
# Necesita Floci levantado y tarda varios minutos; no se ejecuta en `make test`.
# Corre sobre una copia temporal para no tocar la inicialización ni el estado del ambiente real.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

wait_for_emulator

# terraform.exe no entiende rutas /tmp de Git Bash: se usa la ruta Windows (cygpath -m) cuando existe.
tmp="$(mktemp -d)"; tmp="$(cygpath -m "$tmp" 2>/dev/null || printf '%s' "$tmp")"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/terraform/envs/$ENV_NAME" "$tmp/scripts"
cp -r "$ROOT/terraform/modules" "$tmp/terraform/modules"
cp "$ROOT/scripts/floci-ip.sh" "$tmp/scripts/"
(cd "$ENV_DIR" && tar --exclude=.terraform --exclude='*.tfstate*' --exclude=kubeconfig.yaml \
  --exclude=secrets.auto.tfvars --exclude=bootstrap -cf - .) | (cd "$tmp/terraform/envs/$ENV_NAME" && tar -xf -)

terraform -chdir="$tmp/terraform/envs/$ENV_NAME" init -backend=false -input=false >/dev/null
terraform -chdir="$tmp/terraform/envs/$ENV_NAME" test -verbose
