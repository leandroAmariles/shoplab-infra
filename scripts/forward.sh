#!/usr/bin/env bash
# Deja los servicios del clúster accesibles en el host: port-forward en segundo plano al ingress (Argo CD y la app) y a
# Grafana, Prometheus y Alertmanager, y al final imprime todas las URLs. `forward.sh stop` los detiene.
# INGRESS_PORT cambia el puerto del ingress (por defecto 8080). Los demás puertos son fijos.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

PID_FILE="$ENV_DIR/.port-forward.pid"
LOG_FILE="$ENV_DIR/.port-forward.log"
INGRESS_PORT="${INGRESS_PORT:-8080}"
KUBECONFIG_FILE="$ENV_DIR/kubeconfig.yaml"

stop_forward() {
  if [ -f "$PID_FILE" ]; then
    while read -r pid; do
      [ -z "$pid" ] || kill "${pid%$'\r'}" >/dev/null 2>&1 || true
    done < "$PID_FILE"
    rm -f "$PID_FILE"
  fi
}

if [ "${1:-}" = stop ]; then
  stop_forward
  exit 0
fi

command -v kubectl >/dev/null || die "kubectl no está instalado: no se puede exponer los servicios"
[ -f "$KUBECONFIG_FILE" ] || die "no existe $KUBECONFIG_FILE: ejecuta make up primero"
kc() { kubectl --kubeconfig "$KUBECONFIG_FILE" "$@"; }

stop_forward
: > "$LOG_FILE"
log "esperando al controlador de ingress-nginx"
kc -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=300s >/dev/null

# Un port-forward por servicio: namespace svc/nombre puerto-local:puerto-del-servicio
start_forward() {
  nohup kubectl --kubeconfig "$KUBECONFIG_FILE" -n "$1" port-forward "svc/$2" "$3" >>"$LOG_FILE" 2>&1 &
  echo $! >> "$PID_FILE"
  disown 2>/dev/null || true
}

# Espera a que el puerto responda algo por HTTP. El código sale por stdout porque MSYS_NO_PATHCONV impide usar
# -o /dev/null con el curl de Windows; cualquier código distinto de 000 prueba que el túnel funciona (un 404 también).
wait_http() {
  local code
  for _ in $(seq 1 15); do
    code="$(curl -s -m 3 -w '%{http_code}' -H "Host: ${2:-localhost}" "http://127.0.0.1:$1/" 2>/dev/null || true)"
    if [ -n "$code" ] && [ "${code: -3}" != 000 ]; then
      return 0
    fi
    sleep 1
  done
  return 1
}

failed=""
forward() { # nombre namespace servicio puerto-local puerto-servicio host-para-probar
  start_forward "$2" "$3" "$4:$5"
  if wait_http "$4" "${6:-localhost}"; then printf -v "st_$1" ok; else printf -v "st_$1" FALLO; failed="$failed $1 ($4)"; fi
}

forward ingress ingress-nginx ingress-nginx-controller "$INGRESS_PORT" 80 argocd.localtest.me
# La observabilidad es opcional para probar la app: si un servicio no existe aún, solo se avisa.
forward grafana monitoring kube-prometheus-stack-grafana 3000 80
forward prometheus monitoring kube-prometheus-stack-prometheus 9090 9090
forward alertmanager monitoring kube-prometheus-stack-alertmanager 9093 9093

mark() { local v="st_$1"; [ "${!v:-}" = ok ] && printf 'ok   ' || printf 'FALLO'; }
# Floci no pasa por port-forward (compose publica 4566 y Floci publica 4500): solo se comprueba que respondan.
curl -fsS -m 3 "$EMULATOR_URL/_localstack/health" >/dev/null 2>&1 && st_floci=ok || st_floci=FALLO
curl -s -m 3 -w '%{http_code}' "http://127.0.0.1:4500/" 2>/dev/null | grep -qv 000 && st_console=ok || st_console=FALLO
cat >&2 <<SUMMARY

[shoplab-infra] Servicios accesibles en tu máquina
  $(mark ingress)  Argo CD       http://argocd.localtest.me:$INGRESS_PORT        usuario admin / contraseña admin
  $(mark ingress)  App ShopLab   http://shoplab.localtest.me:$INGRESS_PORT       (/api -> backend, / -> frontend)
  $(mark grafana)  Grafana       http://localhost:3000                       usuario admin; contraseña:
                                 kubectl --kubeconfig $KUBECONFIG_FILE -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d
  $(mark prometheus)  Prometheus    http://localhost:9090
  $(mark alertmanager)  Alertmanager  http://localhost:9093
  $(mark floci)  Floci (API AWS) http://localhost:4566
  $(mark console)  Floci (consola) http://localhost:4500
  Detener los túneles: make down (o bash scripts/forward.sh stop). Relanzarlos: make forward
SUMMARY

if [ -n "$failed" ]; then
  log "no respondieron:$failed. Revisa $LOG_FILE (¿puerto ocupado?)"
  exit 1
fi
