#!/usr/bin/env bash
# Pruebas sin emulador: formato, estructura, pines, validación de ambientes y `terraform test` de cada módulo (con mocks).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "terraform fmt -check"
terraform -chdir="$ROOT/terraform" fmt -check -recursive

bash "$ROOT/scripts/check-layout.sh"
bash "$ROOT/scripts/check-pins.sh"

for module in "$ROOT"/terraform/modules/*/; do
  name="$(basename "$module")"
  log "terraform test: módulo $name"
  terraform -chdir="$module" init -backend=false -input=false >/dev/null
  terraform -chdir="$module" test
done

# validate de cada ambiente sobre una copia temporal: no toca el .terraform/estado del ambiente real.
for env_dir in "$ROOT"/terraform/envs/*/; do
  name="$(basename "$env_dir")"
  # terraform.exe no entiende rutas /tmp de Git Bash: se usa la ruta Windows (cygpath -m) cuando existe.
  tmp="$(mktemp -d)"; tmp="$(cygpath -m "$tmp" 2>/dev/null || printf '%s' "$tmp")"
  mkdir -p "$tmp/terraform"
  cp -r "$ROOT/terraform/modules" "$tmp/terraform/modules"
  mkdir -p "$tmp/terraform/envs/$name"
  (cd "$env_dir" && tar --exclude=.terraform --exclude='*.tfstate*' --exclude=kubeconfig.yaml -cf - .) \
    | (cd "$tmp/terraform/envs/$name" && tar -xf -)
  log "terraform validate: ambiente $name"
  terraform -chdir="$tmp/terraform/envs/$name" init -backend=false -input=false >/dev/null
  terraform -chdir="$tmp/terraform/envs/$name" validate
  rm -rf "$tmp"
done

log "pruebas correctas"
