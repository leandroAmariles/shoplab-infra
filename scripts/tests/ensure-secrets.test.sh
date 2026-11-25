#!/usr/bin/env bash
# Pruebas de scripts/ensure-secrets.sh sobre archivos temporales (sin Docker ni Terraform). El script completa
# secrets.auto.tfvars con lo que falte para que `make up` deje LiteLLM, Langfuse y el token del historial de evaluación
# (LAB-31) con credenciales (LAB-29). Lo que
# garantiza: solo AÑADE (nunca cambia un valor que ya hay, p. ej. postgres-password, que debe coincidir con el Postgres de
# Docker) y nunca imprime un valor, solo los nombres de lo que añadió.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
script="$here/../ensure-secrets.sh"
fail=0

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bs='\'; q='"'

ok() { echo "ok    $1"; }
bad() { echo "FALLA $1"; fail=1; }
expect() { # descripción condición(0 = se cumple)
  if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1"; fi
}

# Una entrada JSON-en-HCL: \"CLAVE\":\"valor\"
value_of() { # archivo clave -> valor (primera aparición)
  local pattern="$bs$q$2$bs$q:$bs$q" line rest
  line="$(grep -F -- "$pattern" "$1" | head -1)"
  rest="${line#*"$pattern"}"
  printf '%s' "${rest%%"$bs$q"*}"
}
has_key() { grep -qF -- "$bs$q$2$bs$q" "$1"; }

# --- los archivos de partida --------------------------------------------------------------------------------------------
legacy() { # el que tiene hoy el equipo: solo postgres-password, llm-api-key y llm-model
  cat <<'EOF'
secrets = {
  postgres-password = "pg-secreto-real-no-tocar"
  llm-api-key       = "llm-secreta-no-tocar"
}

parameters = {
  llm-model = "llama3.2:3b"
}
EOF
}

LANGFUSE='{\"POSTGRES_PASSWORD\":\"a\",\"CLICKHOUSE_PASSWORD\":\"a\",\"REDIS_AUTH\":\"a\",\"MINIO_ROOT_PASSWORD\":\"a\",\"SALT\":\"a\",\"ENCRYPTION_KEY\":\"a\",\"NEXTAUTH_SECRET\":\"a\",\"LANGFUSE_INIT_PROJECT_PUBLIC_KEY\":\"a\",\"LANGFUSE_INIT_PROJECT_SECRET_KEY\":\"a\",\"LANGFUSE_INIT_USER_PASSWORD\":\"a\"}'
LITELLM_OLD='{\"LITELLM_MASTER_KEY\":\"sk-maestra-existente\",\"LITELLM_KEY_BACKEND\":\"sk-backend-existente\",\"LITELLM_KEY_INGEST\":\"sk-ingest-existente\",\"POSTGRES_PASSWORD\":\"pg-litellm-existente\"}'
EVAL='{\"EVAL_PERSISTENCE_TOKEN\":\"token-eval-existente-no-tocar\"}'
LITELLM_FULL='{\"LITELLM_MASTER_KEY\":\"sk-maestra-existente\",\"LITELLM_KEY_BACKEND\":\"sk-backend-existente\",\"LITELLM_KEY_INGEST\":\"sk-ingest-existente\",\"LITELLM_KEY_EVAL\":\"sk-eval-existente\",\"LITELLM_KEY_RETRIEVAL\":\"sk-retrieval-existente\",\"POSTGRES_PASSWORD\":\"pg-litellm-existente\"}'

with_entries() { # litellm-json -> archivo con langfuse y litellm
  cat <<EOF
secrets = {
  postgres-password = "pg-secreto-real-no-tocar"
  llm-api-key       = "llm-secreta-no-tocar"
  langfuse = "$LANGFUSE"
  litellm = "$1"
  eval = "$EVAL"
}

parameters = {
  llm-model = "llama3.2:3b"
}
EOF
}

run_script() { # archivo -> salida combinada en $out, código en $code
  out="$(env -u TF_VAR_secrets SECRETS_FILE="$1" bash "$script" 2>&1)"; code=$?
}
all_lines_survive() { # original archivo
  local line
  while IFS= read -r line; do
    [ -z "$line" ] || grep -qxF -- "$line" "$2" || return 1
  done < "$1"
}

# 1. El archivo de hoy: se añaden langfuse y litellm completos, sin tocar nada de lo existente --------------------------
f="$tmp/legacy.tfvars"; legacy > "$f"; cp "$f" "$tmp/legacy.orig"
run_script "$f"
expect "archivo de hoy: termina bien" "$code"
all_lines_survive "$tmp/legacy.orig" "$f"; expect "no cambia ni una línea que ya había" "$?"
grep -qE '^[[:space:]]*langfuse[[:space:]]*=' "$f"; expect "añade la entrada langfuse" "$?"
grep -qE '^[[:space:]]*litellm[[:space:]]*=' "$f"; expect "añade la entrada litellm" "$?"
for key in POSTGRES_PASSWORD CLICKHOUSE_PASSWORD REDIS_AUTH MINIO_ROOT_PASSWORD SALT ENCRYPTION_KEY NEXTAUTH_SECRET \
  LANGFUSE_INIT_PROJECT_PUBLIC_KEY LANGFUSE_INIT_PROJECT_SECRET_KEY LANGFUSE_INIT_USER_PASSWORD \
  LITELLM_MASTER_KEY LITELLM_KEY_BACKEND LITELLM_KEY_INGEST LITELLM_KEY_EVAL; do
  has_key "$f" "$key" || { bad "falta la clave $key"; continue; }
done
has_key "$f" LITELLM_KEY_EVAL; expect "incluye LITELLM_KEY_EVAL" "$?"
grep -qE '^[[:space:]]*eval[[:space:]]*=' "$f"; expect "añade la entrada eval (LAB-31)" "$?"
has_key "$f" EVAL_PERSISTENCE_TOKEN; expect "incluye EVAL_PERSISTENCE_TOKEN" "$?"

# 2. Formatos que exigen el gateway y Langfuse -------------------------------------------------------------------------------
enc="$(value_of "$f" ENCRYPTION_KEY)"
[[ "$enc" =~ ^[0-9a-f]{64}$ ]]; expect "ENCRYPTION_KEY son 64 hexadecimales (openssl rand -hex 32)" "$?"
[[ "$(value_of "$f" LANGFUSE_INIT_PROJECT_PUBLIC_KEY)" =~ ^pk-lf-[0-9a-f]{32}$ ]]; expect "clave pública de Langfuse pk-lf-…" "$?"
[[ "$(value_of "$f" LANGFUSE_INIT_PROJECT_SECRET_KEY)" =~ ^sk-lf-[0-9a-f]{32}$ ]]; expect "clave secreta de Langfuse sk-lf-…" "$?"
for key in LITELLM_MASTER_KEY LITELLM_KEY_BACKEND LITELLM_KEY_INGEST LITELLM_KEY_EVAL; do
  value="$(value_of "$f" "$key")"
  [[ "$value" =~ ^sk-[0-9a-f]{32}$ ]] && [[ "$value" != *change-me* ]] && [[ "$value" != *local* ]]
  expect "$key: sk-… sin marcadores change-me ni local (el Job los rechaza en dev)" "$?"
done
[[ "$(value_of "$f" LANGFUSE_INIT_USER_PASSWORD)" =~ ^[0-9a-zA-Z]{8,}$ ]]; expect "contraseña del usuario inicial: sin caracteres especiales" "$?"
[[ "$(value_of "$f" EVAL_PERSISTENCE_TOKEN)" =~ ^[0-9a-f]{64}$ ]]; expect "EVAL_PERSISTENCE_TOKEN son 64 hexadecimales" "$?"
specials="$(grep -E '^[[:space:]]*(langfuse|litellm|eval)' "$f" | grep -oE "$bs$q[A-Z_]+$bs$q:$bs$q[^$bs]*" | sed 's/.*:\\"//' | grep -cE '[^0-9a-zA-Z-]' || true)"
[ "${specials:-0}" -eq 0 ]; expect "ningún valor generado lleva caracteres especiales" "$?"

# 3. Nunca imprime un valor, solo nombres -----------------------------------------------------------------------------------
leaked=0
for key in ENCRYPTION_KEY LITELLM_KEY_EVAL LANGFUSE_INIT_PROJECT_SECRET_KEY LITELLM_MASTER_KEY EVAL_PERSISTENCE_TOKEN; do
  value="$(value_of "$f" "$key")"; [ -n "$value" ] && [[ "$out" == *"$value"* ]] && leaked=1
done
[[ "$out" != *pg-secreto-real-no-tocar* ]] && [ "$leaked" -eq 0 ]; expect "la salida no contiene ningún valor" "$?"
[[ "$out" == *LITELLM_KEY_EVAL* ]] && [[ "$out" == *langfuse* ]]; expect "la salida nombra lo que añadió" "$?"
[[ "$out" == *eval.EVAL_PERSISTENCE_TOKEN* ]]; expect "la salida nombra la clave eval que añadió y no su valor" "$?"

# 4. Segunda ejecución: no cambia nada y no informa de añadidos --------------------------------------------------------------
before="$(cksum < "$f")"
run_script "$f"
[ "$code" -eq 0 ] && [ "$(cksum < "$f")" = "$before" ]; expect "segunda ejecución: el archivo no cambia (mismo cksum)" "$?"
[[ "$out" != *añadid* ]]; expect "segunda ejecución: no informa de añadidos" "$?"

# 5. litellm existente sin LITELLM_KEY_EVAL: solo se inserta esa clave -------------------------------------------------------
f="$tmp/old-litellm.tfvars"; with_entries "$LITELLM_OLD" > "$f"; cp "$f" "$tmp/old-litellm.orig"
run_script "$f"
expect "litellm sin clave eval: termina bien" "$code"
has_key "$f" LITELLM_KEY_EVAL; expect "inserta LITELLM_KEY_EVAL en el JSON existente" "$?"
for existing in sk-maestra-existente sk-backend-existente sk-ingest-existente pg-litellm-existente pg-secreto-real-no-tocar; do
  grep -qF -- "$existing" "$f" || bad "perdió el valor existente $existing"
done
[[ "$(value_of "$f" LITELLM_MASTER_KEY)" == sk-maestra-existente ]]; expect "las otras claves de litellm conservan su valor" "$?"
[[ "$(grep -c -E '^[[:space:]]*litellm' "$f")" -eq 1 ]]; expect "no duplica la entrada litellm" "$?"
[[ "$out" == *LITELLM_KEY_EVAL* ]] && [[ "$out" != *sk-eval* ]]; expect "informa del nombre añadido y no del valor" "$?"

# 6. Archivo completo: no se toca --------------------------------------------------------------------------------------------
f="$tmp/complete.tfvars"; with_entries "$LITELLM_FULL" > "$f"; before="$(cksum < "$f")"
run_script "$f"
[ "$code" -eq 0 ] && [ "$(cksum < "$f")" = "$before" ]; expect "archivo completo: queda idéntico" "$?"

# 7. Terminaciones de línea de Windows ---------------------------------------------------------------------------------------
f="$tmp/crlf.tfvars"; legacy | sed 's/$/\r/' > "$f"
run_script "$f"
[ "$code" -eq 0 ] && has_key "$f" LITELLM_KEY_EVAL; expect "con CRLF también completa el archivo" "$?"
grep -qF 'postgres-password = "pg-secreto-real-no-tocar"' "$f"; expect "con CRLF conserva postgres-password" "$?"

# 8. Errores -----------------------------------------------------------------------------------------------------------------
run_script "$tmp/no-existe.tfvars"
[ "$code" -ne 0 ] && [[ "$out" == *secrets.auto.tfvars.example* ]]; expect "archivo inexistente: error que remite al ejemplo" "$?"

f="$tmp/raro.tfvars"; printf 'otra_cosa = 1\nsecrets_en_otro_formato: si\n' > "$f"; cp "$f" "$tmp/raro.orig"
run_script "$f"
[ "$code" -ne 0 ] && [[ "$out" == *"a mano"* ]] && cmp -s "$f" "$tmp/raro.orig"; expect "formato irreconocible: error que dice qué añadir a mano y no modifica el archivo" "$?"

f="$tmp/sin-postgres.tfvars"; printf 'secrets = {\n  llm-api-key = "x"\n}\n' > "$f"; cp "$f" "$tmp/sin-postgres.orig"
run_script "$f"
[ "$code" -ne 0 ] && [[ "$out" == *postgres-password* ]] && cmp -s "$f" "$tmp/sin-postgres.orig"; expect "sin postgres-password: no lo inventa (debe coincidir con Postgres) y no modifica el archivo" "$?"

# 9. TF_VAR_secrets: no toca ningún archivo; solo comprueba que estén las claves ---------------------------------------------
f="$tmp/untouched.tfvars"; legacy > "$f"; cp "$f" "$tmp/untouched.orig"
names_complete='{"postgres-password"="x","llm-api-key"="y","langfuse"="{\"POSTGRES_PASSWORD\":\"1\",\"CLICKHOUSE_PASSWORD\":\"1\",\"REDIS_AUTH\":\"1\",\"MINIO_ROOT_PASSWORD\":\"1\",\"SALT\":\"1\",\"ENCRYPTION_KEY\":\"1\",\"NEXTAUTH_SECRET\":\"1\",\"LANGFUSE_INIT_PROJECT_PUBLIC_KEY\":\"1\",\"LANGFUSE_INIT_PROJECT_SECRET_KEY\":\"1\",\"LANGFUSE_INIT_USER_PASSWORD\":\"1\"}","litellm"="{\"LITELLM_MASTER_KEY\":\"1\",\"LITELLM_KEY_BACKEND\":\"1\",\"LITELLM_KEY_INGEST\":\"1\",\"LITELLM_KEY_EVAL\":\"1\",\"LITELLM_KEY_RETRIEVAL\":\"1\",\"POSTGRES_PASSWORD\":\"1\"}"}'
out="$(TF_VAR_secrets="$names_complete" SECRETS_FILE="$f" bash "$script" 2>&1)"; code=$?
[ "$code" -eq 0 ] && cmp -s "$f" "$tmp/untouched.orig"; expect "TF_VAR_secrets completa: sale bien y no toca el archivo" "$?"
[[ "$out" == *aviso* ]] && [[ "$out" == *EVAL_PERSISTENCE_TOKEN* ]]; expect "TF_VAR_secrets sin eval: avisa de que es opcional y no falla" "$?"
names_missing="${names_complete/\\\"LITELLM_KEY_EVAL\\\":\\\"1\\\",/}"
out="$(TF_VAR_secrets="$names_missing" SECRETS_FILE="$f" bash "$script" 2>&1)"; code=$?
[ "$code" -ne 0 ] && [[ "$out" == *LITELLM_KEY_EVAL* ]] && cmp -s "$f" "$tmp/untouched.orig"; expect "TF_VAR_secrets sin la clave eval: error que la nombra y no toca el archivo" "$?"

# 10. La entrada eval (LAB-31): solo se añade, nunca cambia un valor existente ------------------------------------------------
f="$tmp/no-eval.tfvars"
cat > "$f" <<EOF
secrets = {
  postgres-password = "pg-secreto-real-no-tocar"
  llm-api-key       = "llm-secreta-no-tocar"
  langfuse = "$LANGFUSE"
  litellm = "$LITELLM_FULL"
}
EOF
cp "$f" "$tmp/no-eval.orig"
run_script "$f"
expect "sin eval: termina bien" "$code"
all_lines_survive "$tmp/no-eval.orig" "$f"; expect "sin eval: no cambia ni una línea que ya había" "$?"
[[ "$(grep -c -E '^[[:space:]]*eval[[:space:]]*=' "$f")" -eq 1 ]]; expect "sin eval: añade una sola entrada eval" "$?"
token="$(value_of "$f" EVAL_PERSISTENCE_TOKEN)"
[[ "$token" =~ ^[0-9a-f]{64}$ ]] && [[ "$out" != *"$token"* ]]; expect "sin eval: el token es hexadecimal y no se imprime" "$?"

EVAL_OTHER='{\"OTRA\":\"valor-existente\"}'
f="$tmp/eval-sin-clave.tfvars"
cat > "$f" <<EOF
secrets = {
  postgres-password = "pg-secreto-real-no-tocar"
  langfuse = "$LANGFUSE"
  litellm = "$LITELLM_FULL"
  eval = "$EVAL_OTHER"
}
EOF
run_script "$f"
has_key "$f" EVAL_PERSISTENCE_TOKEN && has_key "$f" OTRA && [[ "$(value_of "$f" OTRA)" == valor-existente ]]
expect "eval sin la clave: la inserta y conserva las otras" "$?"
[[ "$(grep -c -E '^[[:space:]]*eval[[:space:]]*=' "$f")" -eq 1 ]]; expect "eval sin la clave: no duplica la entrada" "$?"

exit "$fail"
