#!/usr/bin/env bash
# Data source "external": lee el k3s.yaml del contenedor que Floci crea para el clúster y devuelve JSON con
# el kubeconfig y las credenciales de cliente. Entrada (stdin): {"container": "...", "endpoint": "https://host:port"}.
set -euo pipefail
export MSYS_NO_PATHCONV=1

input="$(cat)"
field() { printf '%s' "$input" | sed -n "s/.*\"$1\" *: *\"\([^\"]*\)\".*/\1/p"; }
container="$(field container)"
endpoint="$(field endpoint)"

# Floci devuelve el clúster ACTIVE antes de que k3s termine de escribir el kubeconfig: se espera.
raw=""
for _ in $(seq 1 60); do
  raw="$(docker exec "$container" cat /etc/rancher/k3s/k3s.yaml 2>/dev/null || true)"
  printf '%s' "$raw" | grep -q 'client-key-data' && break
  sleep 2
done
printf '%s' "$raw" | grep -q 'client-key-data' || { echo "no se pudo leer k3s.yaml de $container" >&2; exit 1; }

value() { printf '%s\n' "$raw" | sed -n "s/.*$1: *//p" | head -n 1 | tr -d '\r'; }
ca="$(value certificate-authority-data)"
cert="$(value client-certificate-data)"
key="$(value client-key-data)"

kubeconfig="apiVersion: v1
kind: Config
clusters:
- name: floci
  cluster:
    server: $endpoint
    certificate-authority-data: $ca
users:
- name: floci-admin
  user:
    client-certificate-data: $cert
    client-key-data: $key
contexts:
- name: floci
  context:
    cluster: floci
    user: floci-admin
current-context: floci
"
escaped="$(printf '%s\n' "$kubeconfig" | awk '{printf "%s\\n", $0}')"
printf '{"kubeconfig":"%s","cluster_ca_certificate":"%s","client_certificate":"%s","client_key":"%s"}\n' \
  "$escaped" "$ca" "$cert" "$key"
