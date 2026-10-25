#!/usr/bin/env bash
# Falla si falta alguno de los cuatro módulos o si un ambiente no tiene su entorno raíz completo (FR-001).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

fail=0
for module in state eks secrets platform; do
  dir="$ROOT/terraform/modules/$module"
  for file in main.tf variables.tf outputs.tf versions.tf; do
    # platform reparte main en varios archivos temáticos; basta con que haya algún .tf de recursos.
    if [ "$file" = main.tf ] && [ "$module" = platform ]; then
      ls "$dir"/*.tf >/dev/null 2>&1 || { log "falta código en modules/$module"; fail=1; }
      continue
    fi
    [ -f "$dir/$file" ] || { log "falta modules/$module/$file"; fail=1; }
  done
  ls "$dir"/tests/*.tftest.hcl >/dev/null 2>&1 || { log "modules/$module no tiene pruebas (tests/*.tftest.hcl)"; fail=1; }
done

envs=0
for env_dir in "$ROOT"/terraform/envs/*/; do
  [ -d "$env_dir" ] || continue
  envs=$((envs + 1))
  for file in main.tf providers.tf backend.tf variables.tf versions.tf .terraform.lock.hcl; do
    [ -f "$env_dir/$file" ] || { log "falta envs/$(basename "$env_dir")/$file"; fail=1; }
  done
done
[ "$envs" -gt 0 ] || { log "no hay ningún ambiente en terraform/envs"; fail=1; }

[ "$fail" -eq 0 ] && log "estructura correcta ($envs ambiente/s)"
exit "$fail"
