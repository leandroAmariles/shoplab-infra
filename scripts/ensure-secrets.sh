#!/usr/bin/env bash
# Completa terraform/envs/dev/secrets.auto.tfvars con lo que falte para que `make up` deje el gateway (LiteLLM) y Langfuse con
# credenciales (LAB-29) y el backend con el token con el que `eval/` guarda las ejecuciones de evaluación (LAB-31). Solo AÑADE: nunca cambia un valor que ya hay (postgres-password debe coincidir con el Postgres de
# Docker) y nunca imprime un valor, solo los nombres de lo que añadió. Idempotente.
# Con TF_VAR_secrets definida no toca ningún archivo: solo comprueba que estén las claves.
# Uso: scripts/ensure-secrets.sh        (SECRETS_FILE cambia el archivo, para las pruebas)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

FILE="${SECRETS_FILE:-$ENV_DIR/secrets.auto.tfvars}"
LANGFUSE_KEYS=(POSTGRES_PASSWORD CLICKHOUSE_PASSWORD REDIS_AUTH MINIO_ROOT_PASSWORD SALT ENCRYPTION_KEY NEXTAUTH_SECRET
  LANGFUSE_INIT_PROJECT_PUBLIC_KEY LANGFUSE_INIT_PROJECT_SECRET_KEY LANGFUSE_INIT_USER_PASSWORD)
LITELLM_KEYS=(LITELLM_MASTER_KEY LITELLM_KEY_BACKEND LITELLM_KEY_INGEST LITELLM_KEY_EVAL POSTGRES_PASSWORD)
# Opcional (LAB-31): sin él el backend no acepta guardar ejecuciones y todo lo demás funciona igual.
EVAL_KEYS=(EVAL_PERSISTENCE_TOKEN)

rand_hex() { # bytes -> 2*bytes caracteres hexadecimales
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex "$1" | tr -d '\r\n'
  else
    od -An -N"$1" -tx1 /dev/urandom | tr -d ' \r\n'
  fi
}

# Los valores usan solo [0-9a-f-]: sin comillas ni barras que rompan el JSON dentro del HCL y sin caracteres que Langfuse
# o la URL de Postgres de LiteLLM interpreten.
value_for() {
  case "$1" in
    ENCRYPTION_KEY) rand_hex 32 ;;                                # 64 hexadecimales: lo que exige Langfuse
    LANGFUSE_INIT_PROJECT_PUBLIC_KEY) printf 'pk-lf-%s' "$(rand_hex 16)" ;;
    LANGFUSE_INIT_PROJECT_SECRET_KEY) printf 'sk-lf-%s' "$(rand_hex 16)" ;;
    LITELLM_MASTER_KEY | LITELLM_KEY_*) printf 'sk-%s' "$(rand_hex 16)" ;;   # sk-…, sin change-me ni local (el Job los rechaza)
    EVAL_PERSISTENCE_TOKEN) rand_hex 32 ;;                        # 64 hexadecimales, sin caracteres especiales
    *) rand_hex 16 ;;
  esac
}

# --- TF_VAR_secrets: solo se comprueba ---------------------------------------------------------------------------------------
if [ -n "${TF_VAR_secrets:-}" ]; then
  flat="${TF_VAR_secrets//\\/}"
  missing=()
  for key in "${LANGFUSE_KEYS[@]}" "${LITELLM_KEYS[@]}"; do
    [[ "$flat" == *"\"$key\""* ]] || missing+=("$key")
  done
  [ "${#missing[@]}" -eq 0 ] || die "TF_VAR_secrets no incluye: ${missing[*]} (con esa variable no se modifica ningún archivo: añádelas tú)"
  [[ "$flat" == *"\"EVAL_PERSISTENCE_TOKEN\""* ]] \
    || log "aviso: TF_VAR_secrets no trae eval.EVAL_PERSISTENCE_TOKEN: el backend no aceptará guardar ejecuciones de evaluación (es opcional)"
  log "TF_VAR_secrets trae todas las claves; no se modifica ningún archivo"
  exit 0
fi

# --- archivo -----------------------------------------------------------------------------------------------------------------
[ -f "$FILE" ] || die "no existe $FILE: cópialo de secrets.auto.tfvars.example y ponle valores locales"

crlf=0
grep -q $'\r' "$FILE" && crlf=1
mapfile -t lines < <(tr -d '\r' < "$FILE")

re_start='^[[:space:]]*secrets[[:space:]]*=[[:space:]]*\{[[:space:]]*$'
re_end='^[[:space:]]*\}[[:space:]]*$'
re_pg='^[[:space:]]*postgres-password[[:space:]]*='
re_lf='^[[:space:]]*langfuse[[:space:]]*='
re_ll='^[[:space:]]*litellm[[:space:]]*='
re_ev='^[[:space:]]*eval[[:space:]]*='
start=-1; end=-1; lf=-1; ll=-1; ev=-1; pg=-1
for i in "${!lines[@]}"; do
  line="${lines[$i]}"
  if [ "$start" -lt 0 ]; then
    if [[ "$line" =~ $re_start ]]; then start=$i; fi
    continue
  fi
  [ "$end" -lt 0 ] || continue
  if [[ "$line" =~ $re_end ]]; then end=$i; continue; fi
  if [[ "$line" =~ $re_pg ]]; then pg=$i; fi
  if [[ "$line" =~ $re_lf ]]; then lf=$i; fi
  if [[ "$line" =~ $re_ll ]]; then ll=$i; fi
  if [[ "$line" =~ $re_ev ]]; then ev=$i; fi
done

[ "$start" -ge 0 ] && [ "$end" -ge 0 ] \
  || die "no reconozco el formato de $FILE (busco un bloque «secrets = { … }»): añade a mano las entradas langfuse y litellm (ver secrets.auto.tfvars.example)"
[ "$pg" -ge 0 ] \
  || die "falta postgres-password en $FILE: debe coincidir con la contraseña de tu Postgres de Docker, así que no la invento; añádela a mano"

ADDED=()
NEW_LINE=""

# Añade al JSON-en-HCL de una línea las claves que falten; deja NEW_LINE y apunta los nombres en ADDED.
extend_json_line() { # línea nombre-de-entrada claves...
  local line="$1" name="$2"; shift 2
  local add="" key needle re='^(.*)\}"([[:space:]]*)$'
  for key in "$@"; do
    needle="\\\"$key\\\""
    if [[ "$line" != *"$needle"* ]]; then
      add+=",\\\"$key\\\":\\\"$(value_for "$key")\\\""
      ADDED+=("$name.$key")
    fi
  done
  NEW_LINE="$line"
  [ -z "$add" ] && return 0
  [[ "$line" =~ $re ]] || die "no sé ampliar la entrada $name de $FILE (no es una sola línea): añade a mano ${ADDED[*]}"
  local prefix="${BASH_REMATCH[1]}" tail="${BASH_REMATCH[2]}"
  [[ "$prefix" == *"{" ]] && add="${add#,}"
  NEW_LINE="${prefix}${add}}\"${tail}"
}

new_entry() { # nombre claves... -> NEW_LINE con la entrada completa
  local name="$1"; shift
  local json="" key
  for key in "$@"; do
    json+="${json:+,}\\\"$key\\\":\\\"$(value_for "$key")\\\""
    ADDED+=("$name.$key")
  done
  NEW_LINE="  $name = \"{$json}\""
}

result=()
for i in "${!lines[@]}"; do
  if [ "$i" -eq "$end" ]; then
    if [ "$lf" -lt 0 ]; then new_entry langfuse "${LANGFUSE_KEYS[@]}"; result+=("$NEW_LINE"); fi
    if [ "$ll" -lt 0 ]; then new_entry litellm "${LITELLM_KEYS[@]}"; result+=("$NEW_LINE"); fi
    if [ "$ev" -lt 0 ]; then new_entry eval "${EVAL_KEYS[@]}"; result+=("$NEW_LINE"); fi
  fi
  if [ "$i" -eq "$lf" ]; then
    extend_json_line "${lines[$i]}" langfuse "${LANGFUSE_KEYS[@]}"; result+=("$NEW_LINE")
  elif [ "$i" -eq "$ll" ]; then
    extend_json_line "${lines[$i]}" litellm "${LITELLM_KEYS[@]}"; result+=("$NEW_LINE")
  elif [ "$i" -eq "$ev" ]; then
    extend_json_line "${lines[$i]}" eval "${EVAL_KEYS[@]}"; result+=("$NEW_LINE")
  else
    result+=("${lines[$i]}")
  fi
done

if [ "${#ADDED[@]}" -eq 0 ]; then
  log "secrets.auto.tfvars ya está completo: no se cambia nada"
  exit 0
fi

if [ "$crlf" -eq 1 ]; then
  printf '%s\n' "${result[@]}" | sed 's/$/\r/' > "$FILE"
else
  printf '%s\n' "${result[@]}" > "$FILE"
fi
log "añadidas ${#ADDED[@]} claves nuevas a $(basename "$FILE") (los valores existentes no se tocan ni se muestran): ${ADDED[*]}"
