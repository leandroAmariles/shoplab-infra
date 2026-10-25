#!/usr/bin/env bash
# Verifica que las herramientas instaladas coinciden con versions.env. Dice cuál falta y cómo instalarla.
# ALLOW_TOOL_DRIFT=1 convierte una versión distinta en aviso (solo para uso local).
# Uso: check-tools.sh [terraform] [tflint] [trivy] [kustomize] [kubeconform] [yq]. Sin argumentos revisa todas (CI revisa solo las que cada job instala).
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# shellcheck disable=SC1091
set -a; source "$ROOT/versions.env"; set +a

fail=0
check() { # nombre versión-esperada versión-instalada instalación
  local name="$1" want="$2" have="$3" hint="$4"
  if [ -z "$have" ]; then
    log "falta $name $want. Instalación: $hint"
    fail=1
  elif [ "$have" != "$want" ]; then
    if [ "${ALLOW_TOOL_DRIFT:-0}" = 1 ]; then
      log "AVISO: $name $have instalado, versions.env pide $want"
    else
      log "$name $have instalado, versions.env pide $want. Instalación: $hint"
      fail=1
    fi
  fi
}

have_terraform="$(terraform version 2>/dev/null | sed -nE '1s/^Terraform v([0-9.]+).*/\1/p' || true)"
have_tflint="$(tflint --version 2>/dev/null | sed -nE '1s/^TFLint version ([0-9.]+).*/\1/p' || true)"
have_trivy="$(trivy --version 2>/dev/null | sed -nE '1s/^Version: ([0-9.]+).*/\1/p' || true)"
have_kustomize="$(kustomize version 2>/dev/null | sed -nE '1s/^v?([0-9.]+).*/\1/p' || true)"
have_kubeconform="$(kubeconform -v 2>/dev/null | sed -nE '1s/^v?([0-9.]+).*/\1/p' || true)"
have_yq="$(yq --version 2>/dev/null | sed -nE '1s/.* version v?([0-9.]+).*/\1/p' || true)"

wanted() { local t; for t in "${TOOLS[@]}"; do [ "$t" = "$1" ] && return 0; done; return 1; }
TOOLS=("$@")
if [ "${#TOOLS[@]}" -eq 0 ]; then TOOLS=(terraform tflint trivy kustomize kubeconform yq); fi

wanted terraform && check terraform "$TERRAFORM_VERSION" "$have_terraform" "https://developer.hashicorp.com/terraform/install"
wanted tflint && check tflint "$TFLINT_VERSION" "$have_tflint" "https://github.com/terraform-linters/tflint/releases/tag/v$TFLINT_VERSION"
wanted trivy && check trivy "$TRIVY_VERSION" "$have_trivy" "https://github.com/aquasecurity/trivy/releases/tag/v$TRIVY_VERSION"
wanted kustomize && check kustomize "$KUSTOMIZE_VERSION" "$have_kustomize" "https://github.com/kubernetes-sigs/kustomize/releases/tag/kustomize%2Fv$KUSTOMIZE_VERSION"
wanted kubeconform && check kubeconform "$KUBECONFORM_VERSION" "$have_kubeconform" "https://github.com/yannh/kubeconform/releases/tag/v$KUBECONFORM_VERSION"
wanted yq && check yq "$YQ_VERSION" "$have_yq" "https://github.com/mikefarah/yq/releases/tag/v$YQ_VERSION"

# El plugin de TFLint y la imagen de Floci deben ser los mismos que en .tflint.hcl y docker-compose.yml.
grep -q "version = \"$TFLINT_AWS_RULESET_VERSION\"" "$ROOT/.tflint.hcl" \
  || { log ".tflint.hcl no usa tflint-ruleset-aws $TFLINT_AWS_RULESET_VERSION (versions.env)"; fail=1; }
grep -qE "image:[[:space:]]*$FLOCI_IMAGE[[:space:]]*$" "$ROOT/docker-compose.yml" \
  || { log "docker-compose.yml no usa la imagen $FLOCI_IMAGE (versions.env)"; fail=1; }

[ "$fail" -eq 0 ] && log "herramientas correctas"
exit "$fail"
