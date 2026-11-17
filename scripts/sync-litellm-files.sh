#!/usr/bin/env bash
# Copia la configuración del gateway desde shoplab-helpdesk (infra/litellm) a k8s/base/litellm/files (LAB-84).
# Así docker compose y el clúster comparten una sola fuente. Ejecútalo tras cualquier cambio en infra/litellm y haz commit del
# resultado: `files/SOURCE` guarda el commit de origen. Uso: scripts/sync-litellm-files.sh [ruta-a-shoplab-helpdesk]
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

SRC_REPO="${1:-${SHOPLAB_HELPDESK_DIR:-$ROOT/../shoplab-helpdesk}}"
SRC="$SRC_REPO/infra/litellm"
DEST="$ROOT/k8s/base/litellm/files"
[ -d "$SRC" ] || die "no existe $SRC (pasa la ruta de shoplab-helpdesk o define SHOPLAB_HELPDESK_DIR)"

mkdir -p "$DEST"
for file in config.yaml keys.yaml entrypoint.sh render_config.py check_models.py bootstrap_keys.py shoplab_callbacks.py; do
  [ -f "$SRC/$file" ] || die "falta $SRC/$file"
  cp "$SRC/$file" "$DEST/$file"
done
commit="$(git -C "$SRC_REPO" rev-parse HEAD 2>/dev/null || echo desconocido)"
dirty=""
[ -z "$(git -C "$SRC_REPO" status --porcelain -- infra/litellm 2>/dev/null)" ] || dirty=" (con cambios sin confirmar)"
printf 'shoplab-helpdesk %s%s\n' "$commit" "$dirty" > "$DEST/SOURCE"
log "sincronizado desde $SRC (${commit:0:12}$dirty)"
