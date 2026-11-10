#!/usr/bin/env bash
# Carga el corpus de la base de conocimiento (data/kb/*.md de shoplab-helpdesk) en el entorno levantado, subiendo cada
# documento a POST /api/documents del backend (que lo trocea, calcula los embeddings y lo guarda). Es idempotente:
# volver a subir un documento lo reemplaza. Hay que repetirlo tras cada make up, porque make down borra la base.
#   KB_DIR        carpeta con los .md (por defecto ../shoplab-helpdesk/data/kb)
#   INGRESS_PORT  puerto del ingress en el host (por defecto 8080; el mismo que usa forward.sh)
#   SEED_TIMEOUT  segundos máximos por documento (por defecto 300: los embeddings corren en CPU)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

KB_DIR="${KB_DIR:-$ROOT/../shoplab-helpdesk/data/kb}"
INGRESS_PORT="${INGRESS_PORT:-8080}"
SEED_TIMEOUT="${SEED_TIMEOUT:-300}"
# Se entra por 127.0.0.1 con la cabecera Host: no depende de que se resuelva *.localtest.me (sin red local falla).
BASE_URL="http://127.0.0.1:$INGRESS_PORT"
HOST_HEADER="Host: shoplab.localtest.me"

[ -d "$KB_DIR" ] || die "no existe $KB_DIR (define KB_DIR con la carpeta data/kb de shoplab-helpdesk)"
command -v curl >/dev/null || die "curl no está instalado"

# INDEX.md y REVIEW.md son metadatos del corpus, no documentos de conocimiento; los PDF duplican a su .md.
files=()
for f in "$KB_DIR"/*.md; do
  case "$(basename "$f")" in INDEX.md | REVIEW.md) continue ;; esac
  files+=("$f")
done
[ "${#files[@]}" -gt 0 ] || die "no hay documentos .md en $KB_DIR"

log "esperando al backend en $BASE_URL"
tries=30
until [ "$(curl -s -m 5 -o /dev/null -w '%{http_code}' -H "$HOST_HEADER" "$BASE_URL/api/documents" 2>/dev/null || true)" = 200 ]; do
  tries=$((tries - 1))
  [ "$tries" -gt 0 ] || die "el backend no responde en $BASE_URL/api/documents (¿make up y make forward ya corrieron?)"
  sleep 4
done

log "cargando ${#files[@]} documentos desde $KB_DIR"
failed=0
for f in "${files[@]}"; do
  name="$(basename "$f")"
  code="$(curl -s -m "$SEED_TIMEOUT" -o /dev/null -w '%{http_code}' -H "$HOST_HEADER" \
    -F "file=@$f;type=text/markdown" "$BASE_URL/api/documents" 2>/dev/null || true)"
  case "$code" in
    200) log "  reemplazado  $name" ;;
    201) log "  cargado      $name" ;;
    *) log "  FALLO ($code) $name"; failed=$((failed + 1)) ;;
  esac
done

[ "$failed" -eq 0 ] || die "$failed documento(s) no se cargaron"
total="$(curl -s -m 10 -H "$HOST_HEADER" "$BASE_URL/api/documents" | grep -o '"name"' | wc -l | tr -d ' ')"
log "listo: $total documentos en la base de conocimiento"
