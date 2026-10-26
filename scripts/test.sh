#!/usr/bin/env bash
# Pruebas sin emulador: formato, estructura, pines, validación de ambientes y `terraform test` de cada módulo (con mocks).
# Uso: test.sh [all|fmt|checks|validate|modules]. Sin argumento corre todo; CI y el Makefile llaman a cada paso por separado.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

step_fmt() {
  log "terraform fmt -check"
  terraform -chdir="$ROOT/terraform" fmt -check -recursive
}

step_checks() {
  bash "$ROOT/scripts/check-layout.sh"
  bash "$ROOT/scripts/check-pins.sh"
}

step_modules() {
  for module in "$ROOT"/terraform/modules/*/; do
    name="$(basename "$module")"
    log "terraform test: módulo $name"
    terraform -chdir="$module" init -backend=false -input=false >/dev/null
    terraform -chdir="$module" test
  done
}

# validate de cada módulo y de cada ambiente (con su bootstrap). Los ambientes se validan sobre una copia temporal:
# no se toca el .terraform/estado del ambiente real.
step_validate() {
  for module in "$ROOT"/terraform/modules/*/; do
    log "terraform validate: módulo $(basename "$module")"
    terraform -chdir="$module" init -backend=false -input=false >/dev/null
    terraform -chdir="$module" validate
  done
  for env_dir in "$ROOT"/terraform/envs/*/; do
    name="$(basename "$env_dir")"
    # terraform.exe no entiende rutas /tmp de Git Bash: se usa la ruta Windows (cygpath -m) cuando existe.
    tmp="$(mktemp -d)"; tmp="$(cygpath -m "$tmp" 2>/dev/null || printf '%s' "$tmp")"
    mkdir -p "$tmp/terraform"
    cp -r "$ROOT/terraform/modules" "$tmp/terraform/modules"
    # El ambiente lee la Application raíz de Argo CD (file() se evalúa en validate): se copia a la misma ruta relativa.
    mkdir -p "$tmp/k8s/argocd"
    cp "$ROOT/k8s/argocd/root.yaml" "$tmp/k8s/argocd/root.yaml"
    mkdir -p "$tmp/terraform/envs/$name"
    (cd "$env_dir" && tar --exclude=.terraform --exclude='*.tfstate*' --exclude=kubeconfig.yaml -cf - .) \
      | (cd "$tmp/terraform/envs/$name" && tar -xf -)
    log "terraform validate: ambiente $name"
    terraform -chdir="$tmp/terraform/envs/$name" init -backend=false -input=false >/dev/null
    terraform -chdir="$tmp/terraform/envs/$name" validate
    # El bootstrap del estado (backend local) es una raíz aparte y debe validarse igual.
    if [ -d "$tmp/terraform/envs/$name/bootstrap" ]; then
      log "terraform validate: bootstrap de $name"
      terraform -chdir="$tmp/terraform/envs/$name/bootstrap" init -backend=false -input=false >/dev/null
      terraform -chdir="$tmp/terraform/envs/$name/bootstrap" validate
    fi
    rm -rf "$tmp"
  done
}

case "${1:-all}" in
  fmt) step_fmt ;;
  checks) step_checks ;;
  modules) step_modules ;;
  validate) step_validate ;;
  all) step_fmt; step_checks; step_modules; step_validate; log "pruebas correctas" ;;
  *) die "uso: test.sh [all|fmt|checks|validate|modules]" ;;
esac
