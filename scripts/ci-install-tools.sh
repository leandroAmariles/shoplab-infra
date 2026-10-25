#!/usr/bin/env bash
# Instala en el runner (Linux amd64) kustomize, kubeconform y yq a las versiones de versions.env, verificando el
# sha256 contra el archivo de sumas que publica cada proyecto. Uso: ci-install-tools.sh [kustomize] [kubeconform] [yq]
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# shellcheck disable=SC1091
set -a; source "$ROOT/versions.env"; set +a
BIN="${INSTALL_DIR:-$HOME/.local/bin}"
mkdir -p "$BIN"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

fetch() { curl -fsSL --retry 3 -o "$2" "$1"; }
verify() { # archivo hash-esperado
  [ -n "$2" ] || die "no hay suma de verificación para $1"
  [ "$(sha256sum "$1" | cut -d' ' -f1)" = "$2" ] || die "sha256 no coincide para $1"
}

install_kustomize() {
  local f="kustomize_v${KUSTOMIZE_VERSION}_linux_amd64.tar.gz" base="https://github.com/kubernetes-sigs/kustomize/releases/download/kustomize%2Fv${KUSTOMIZE_VERSION}"
  fetch "$base/$f" "$tmp/$f"; fetch "$base/checksums.txt" "$tmp/kustomize.sums"
  verify "$tmp/$f" "$(awk -v f="$f" '$2 == f {print $1}' "$tmp/kustomize.sums")"
  tar -xzf "$tmp/$f" -C "$BIN" kustomize
}
install_kubeconform() {
  local f="kubeconform-linux-amd64.tar.gz" base="https://github.com/yannh/kubeconform/releases/download/v${KUBECONFORM_VERSION}"
  fetch "$base/$f" "$tmp/$f"; fetch "$base/CHECKSUMS" "$tmp/kubeconform.sums"
  verify "$tmp/$f" "$(awk -v f="$f" '$2 == f {print $1}' "$tmp/kubeconform.sums")"
  tar -xzf "$tmp/$f" -C "$BIN" kubeconform
}
install_yq() {
  local f="yq_linux_amd64" base="https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}"
  fetch "$base/$f" "$tmp/$f"; fetch "$base/checksums-bsd" "$tmp/yq.sums"
  verify "$tmp/$f" "$(sed -nE "s/^SHA256 \($f\) = ([0-9a-f]+)\$/\1/p" "$tmp/yq.sums")"
  install -m 0755 "$tmp/$f" "$BIN/yq"
}

TOOLS=("$@"); [ "${#TOOLS[@]}" -gt 0 ] || TOOLS=(kustomize kubeconform yq)
for t in "${TOOLS[@]}"; do
  log "instalando $t"
  "install_$t"
done
[ -z "${GITHUB_PATH:-}" ] || echo "$BIN" >> "$GITHUB_PATH"
