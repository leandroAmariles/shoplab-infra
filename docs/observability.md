# Observabilidad del backend en el clúster

Qué instala y gestiona este repositorio para ver las métricas del backend (LAB-102). Las métricas, los dashboards y su
uso local con docker compose están en `docs/observabilidad.md` de `shoplab-helpdesk`; la decisión, en su ADR-0009.

## Qué hay en el clúster

| Recurso | Dónde se define | Quién lo gestiona |
| --- | --- | --- |
| kube-prometheus-stack con Alertmanager activo | `terraform/modules/platform/monitoring.tf` | Terraform (`make up`) |
| `ServiceMonitor/backend` | `k8s/base/backend/servicemonitor.yaml` | Argo CD (`shoplab-dev`) |
| `PrometheusRule/backend` (alerta `BackendDown`) | `k8s/base/backend/prometheusrule.yaml` | Argo CD (`shoplab-dev`) |
| Dashboards de Grafana (3 `ConfigMap` en `monitoring`) | `infra/observability/` de **shoplab-helpdesk** | Argo CD (`shoplab-observability`) |

- Prometheus selecciona **todos** los `ServiceMonitor` y `PrometheusRule` (`serviceMonitorSelectorNilUsesHelmValues` y
  `ruleSelectorNilUsesHelmValues` en `false`): no hace falta la etiqueta `release: kube-prometheus-stack` en los manifiestos.
- Alertmanager pide 10m de CPU y 32Mi de memoria, sin almacenamiento (el k3s de Floci no trae `StorageClass`) y sin receptores.
- El `ServiceMonitor` recoge el puerto `http` del `Service` `backend` en `/actuator/prometheus` cada 30 s; el `job` es `backend`.
  El ingress no publica esa ruta (solo `/api` y `/`).
- La Application `shoplab-observability` (`k8s/argocd/application-observability.yaml`) lee `infra/observability` de
  `shoplab-helpdesk` en `main`, con `prune`, `selfHeal` y `ServerSideApply`. Un dashboard fusionado allí llega solo al
  clúster; la PR de `shoplab-helpdesk` debe fusionarse antes que la que añade esta Application.

## La alerta BackendDown

`up{job="backend",namespace="shoplab-dev"} == 0 or absent(up{...})` durante 2 minutos, severidad `critical`. El `absent()`
cubre 0 réplicas o un `Deployment` borrado, caso en el que la serie `up` desaparece y `up == 0` nunca se cumpliría.

Prueba local, sin clúster: `make prom-rules` renderiza el overlay `dev`, extrae la regla y ejecuta `promtool check rules` y
`promtool test rules` con `rules-tests/backend-down.test.yaml` (5 casos). `promtool` se fija en `versions.env`
(`PROMTOOL_VERSION`) y lo instala `scripts/ci-install-tools.sh` en el CI. Ajustar el umbral (`for`) o la expresión exige
actualizar esa prueba en la misma PR.

## Verlo en el clúster local

```bash
kubectl -n monitoring port-forward svc/kube-prometheus-stack-prometheus 9090:9090 &
kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana 3000:80 &
kubectl -n monitoring port-forward svc/kube-prometheus-stack-alertmanager 9093:9093 &
curl -s localhost:9090/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="backend") | .health'
kubectl -n argocd get applications     # shoplab-root, shoplab-dev y shoplab-observability en Synced
```

Los nombres de los `Service` dependen del release (`kube-prometheus-stack`). Si el backend aparece como caído justo tras
fusionar, es lo esperado hasta que el despliegue continuo (LAB-81) publique una imagen que ya expone `/actuator/prometheus`.

## Langfuse (LAB-64)

Langfuse guarda una traza por cada turno del chat (pregunta, prompt, fragmentos recuperados con su puntuación, herramientas,
tokens y coste). En `shoplab-dev` Argo CD despliega seis cargas desde `k8s/base/langfuse/`, todas con versión fija y
`securityContext` endurecido:

| Carga | Tipo | Imagen | Datos |
|---|---|---|---|
| `langfuse-web` (3000) y `langfuse-worker` (3030) | Deployment | `langfuse:4.77.0`, `langfuse-worker:4.77.0` | sin estado |
| `langfuse-postgres` | StatefulSet | `postgres:17.7` | PVC `local-path` de 2Gi |
| `langfuse-clickhouse` | StatefulSet | `clickhouse-server:26.3.62.3` | PVC de 5Gi |
| `langfuse-redis` | StatefulSet | `redis:7.4.6` | PVC de 1Gi |
| `langfuse-minio` | StatefulSet | `chainguard/minio` por digest | PVC de 2Gi |

Todos los `Service` son `ClusterIP`: **no hay Ingress ni NodePort** (los almacenes nunca se publican). El backend de dev
envía las trazas a `http://langfuse-web:3000/api/public/otel` (ver `SHOPLAB_CHAT_TRACING_*` en el overlay `dev`) con las
claves del proyecto, que salen del mismo secreto que usa Langfuse para crearlo.

### Acceso a la interfaz

```bash
kubectl -n shoplab-dev port-forward svc/langfuse-web 3001:3000
# http://localhost:3001  (usuario admin@shoplab.local, contraseña = LANGFUSE_INIT_USER_PASSWORD del secreto)
```

Es el puerto 3001 porque `NEXTAUTH_URL` vale `http://localhost:3001`; con otro puerto local el inicio de sesión falla.

### El secreto `/shoplab/dev/langfuse`

Un solo secreto de Secrets Manager con un JSON de diez claves (Terraform lo crea al ser `langfuse` un secreto requerido de
`terraform/modules/secrets`). Cada clave se convierte en una clave del Secret `langfuse-credentials`:

| Clave | Uso |
|---|---|
| `POSTGRES_PASSWORD`, `CLICKHOUSE_PASSWORD`, `REDIS_AUTH`, `MINIO_ROOT_PASSWORD` | contraseñas de los cuatro almacenes |
| `SALT`, `NEXTAUTH_SECRET` | secretos de la aplicación |
| `ENCRYPTION_KEY` | 64 caracteres hexadecimales (`openssl rand -hex 32`) |
| `LANGFUSE_INIT_PROJECT_PUBLIC_KEY`, `LANGFUSE_INIT_PROJECT_SECRET_KEY` | claves del proyecto (`pk-lf-…`, `sk-lf-…`); también las lee el backend |
| `LANGFUSE_INIT_USER_PASSWORD` | contraseña del usuario inicial |

Cárgalo desde `terraform/envs/dev/secrets.auto.tfvars` (no versionado; el ejemplo está en
`secrets.auto.tfvars.example`) como una cadena JSON en la entrada `langfuse`. Evita caracteres especiales en
`POSTGRES_PASSWORD`: va dentro de la `DATABASE_URL`.

### Qué se conserva

Los datos viven en PVC `local-path` del nodo: sobreviven a reinicios de los pods, **no** a `make down`/`destroy` del clúster.
Tras `make down && make up` Langfuse vuelve sin pasos manuales (organización, proyecto y claves los crea `LANGFUSE_INIT_*`),
pero sin las trazas anteriores.
