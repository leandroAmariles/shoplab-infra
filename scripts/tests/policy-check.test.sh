#!/usr/bin/env bash
# Pruebas de scripts/policy-check.sh sobre scripts/tests/fixtures (contracts/policy-rules.md de LAB-99).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
check="$here/../policy-check.sh"
fail=0

expect() { # fixture código-esperado [regla]
  local out code
  out="$(bash "$check" "$here/fixtures/$1/rendered.yaml" "$1" 2>&1)"; code=$?
  if [ "$code" -ne "$2" ] || { [ -n "${3:-}" ] && ! grep -q "^$3 |" <<< "$out"; }; then
    echo "FALLA $1: salida $code (esperada $2${3:+, regla $3})"; echo "$out" | sed 's/^/    /'; fail=1
  else
    echo "ok    $1 -> $2${3:+ $3}"
  fi
}

expect good 0
expect bad-latest 1 IMAGE_LATEST
expect bad-notag 1 IMAGE_NO_TAG
expect bad-portnotag 1 IMAGE_NO_TAG
expect bad-repourl 1 TEMPLATE_REPO_URL
expect bad-revision 1 TARGET_REVISION_NOT_MAIN
expect good-externalsecret 0
expect bad-secret 1 PLAIN_SECRET

bash "$check" /no/existe.yaml >/dev/null 2>&1; code=$?
if [ "$code" -eq 2 ]; then echo "ok    archivo inexistente -> 2"; else echo "FALLA archivo inexistente: salida $code (esperada 2)"; fail=1; fi

exit "$fail"
