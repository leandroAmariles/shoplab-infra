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
