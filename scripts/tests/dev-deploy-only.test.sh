#!/usr/bin/env bash
# Pruebas de scripts/is-dev-deploy-only.sh sobre un repositorio git temporal: solo un cambio de `newTag` en
# k8s/overlays/dev/kustomization.yaml (el commit automático de despliegue de LAB-81) permite omitir la prueba de humo.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../is-dev-deploy-only.sh"
fail=0

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
git -C "$tmp" init -q
git -C "$tmp" config user.email test@example.com; git -C "$tmp" config user.name test; git -C "$tmp" config core.autocrlf false
mkdir -p "$tmp/k8s/overlays/dev"
overlay="$tmp/k8s/overlays/dev/kustomization.yaml"
tag_a=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; tag_b=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
write_overlay() { # tag namespace
  printf 'namespace: %s\nimages:\n- name: backend\n  newName: ghcr.io/o/backend\n  newTag: %s\n- name: frontend\n  newName: ghcr.io/o/frontend\n  newTag: %s\n' \
    "$2" "$1" "$1" > "$overlay"
}
commit() { git -C "$tmp" add -A && git -C "$tmp" commit -q -m "$1" && git -C "$tmp" rev-parse HEAD; }

write_overlay "$tag_a" shoplab-dev; echo base > "$tmp/README.md"; c0="$(commit base)"
write_overlay "$tag_b" shoplab-dev;                              c_tags="$(commit 'solo tags')"
write_overlay "$tag_a" otro-namespace;                           c_ns="$(commit 'cambia el namespace')"
write_overlay "$tag_b" otro-namespace; echo more >> "$tmp/README.md"; c_two="$(commit 'tags y otro archivo')"
echo more >> "$tmp/README.md";                                   c_readme="$(commit 'solo README')"
write_overlay "$tag_a" otro-namespace;                           c_back="$(commit 'tags otra vez')"
write_overlay "$tag_b" distinto-namespace;                       c_mixed="$(commit 'tag y namespace en el mismo archivo')"

expect() { # descripción código-esperado antes después
  local desc="$1" want="$2" code
  (cd "$tmp" && bash "$script" "$3" "$4" >/dev/null 2>&1); code=$?
  if [ "$code" -eq "$want" ]; then echo "ok    $desc -> $want"; else echo "FALLA $desc: salida $code (esperada $want)"; fail=1; fi
}

expect "solo cambian los tags de imagen" 0 "$c0" "$c_tags"
expect "cambia el namespace del overlay" 1 "$c_tags" "$c_ns"
expect "tags y otro archivo a la vez" 1 "$c_ns" "$c_two"
expect "solo cambia un archivo ajeno" 1 "$c_two" "$c_readme"
expect "tags otra vez (otro valor)" 0 "$c_readme" "$c_back"
expect "tag y namespace en el mismo archivo" 1 "$c_back" "$c_mixed"
expect "rango de varios commits con un cambio ajeno" 1 "$c0" "$c_two"
expect "antes vacío" 1 "" "$c_tags"
expect "antes todo ceros (rama nueva)" 1 0000000000000000000000000000000000000000 "$c_tags"
expect "commit anterior desconocido" 1 1111111111111111111111111111111111111111 "$c_tags"

exit "$fail"
