# Manifiestos con Kustomize (`k8s/`)

El despliegue de ShopLab se describe de forma declarativa con Kustomize: una **base** común y un **overlay** por
ambiente (`dev`, `staging`, `prod`). Argo CD sincroniza el overlay desde `main`.

## Estructura

```text
k8s/
├── base/                    # backend, frontend, ingest, postgres (pgvector), ollama e ingress
│   ├── kustomization.yaml
│   └── <componente>/        # workload, service, ConfigMap generado y, si lleva credenciales, ExternalSecret
├── overlays/<ambiente>/     # namespace, imágenes de la app, recursos, HPA, host y claves de Secrets Manager
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── hpa.yaml
│   └── patches/resources.yaml
└── argocd/                  # Application raíz (root.yaml) y una por ambiente (application-<ambiente>.yaml)
```

La base no se despliega sola: no define namespace ni tags efectivos de las imágenes de la aplicación. Cada overlay
las fija. Kafka y los servicios de F4 no están en la base; se añaden como un componente más.

## Qué cambia por ambiente

| | dev | staging | prod |
| --- | --- | --- | --- |
| Namespace | `shoplab-dev` | `shoplab-staging` | `shoplab-prod` |
| HPA backend (mín–máx, CPU) | 1–2, 75% | 2–4, 70% | 3–8, 70% |
| HPA frontend | 1–2, 75% | 2–3, 70% | 2–6, 70% |
| HPA ingest | 1–2, 75% | 1–2, 70% | 2–4, 70% |
| Postgres / Ollama (PVC) | 5Gi / 10Gi | 20Gi / 20Gi | 50Gi / 40Gi |
| Host del ingress | `shoplab.localtest.me` | `staging.shoplab.example` | `shoplab.example` |
| Nivel de log del backend | `DEBUG` | `INFO` | `INFO` |

Los recursos por componente están en `overlays/<ambiente>/patches/resources.yaml`. Postgres y Ollama son de una
réplica y no escalan con HPA. Los Deployments no fijan `replicas`: las gobierna el HPA.

## Imágenes

Backend, frontend e ingest usan `ghcr.io/leandroamariles/<servicio>` y se fijan en `images:` de cada overlay. Hoy
van por **digest** de la imagen construida desde `main`, porque los tags `vX.Y.Z` (inmutables, LAB-78) aún no existen
en GHCR. Para obtener el digest de un commit:
`curl -sI -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.oci.image.index.v1+json" https://ghcr.io/v2/leandroamariles/<servicio>/manifests/<sha-completo>`
(cabecera `docker-content-digest`; el token anónimo sale de `https://ghcr.io/token?scope=repository:leandroamariles/<servicio>:pull`).
Cuando se publiquen los tags de versión, cada ambiente se promueve con `newTag: vX.Y.Z`. Postgres (`pgvector/pgvector`) y Ollama
llevan su versión en la base, la misma que `docker-compose.yml` de `shoplab-helpdesk`. Ninguna imagen puede usar
`latest` ni quedar sin tag: lo comprueba `scripts/policy-check.sh`.

## Secretos

No hay recursos `Secret` en git (regla `PLAIN_SECRET`). Cada componente que necesita una credencial declara un
`ExternalSecret` que lee de Secrets Manager mediante el `ClusterSecretStore` `aws-secrets-manager` (LAB-98). La base
usa la clave `/shoplab/ENVIRONMENT/postgres-password` y cada overlay sustituye `ENVIRONMENT` por su nombre, de modo que
un ambiente solo lee sus propias claves. Los valores los crea el módulo `secrets` de Terraform. Como la `Application`
raíz de Argo CD despliega los tres ambientes, `make up` crea por defecto las claves `/shoplab/<ambiente>/...` de `dev`,
`staging` y `prod` (variable `app_environments`); para crear solo algunas:

```bash
TF_VAR_app_environments='["dev"]' make up
```

## Desplegar un overlay en el clúster local

`make up` deja Argo CD con la `Application` raíz `shoplab-root`, que crea `shoplab-dev`, `shoplab-staging` y
`shoplab-prod` desde `main`: no hay que aplicar nada a mano. El flujo completo y cómo entrar a la interfaz están en
[`gitops.md`](gitops.md).

El k3s de Floci no trae `StorageClass`, así que los PVC de Postgres y Ollama quedan en `Pending` hasta que el clúster
tenga una por defecto (en un EKS real se usa la del clúster). En local basta una clase sin provisionador con un PV
`hostPath` por PVC (5Gi para `data-postgres-0` y 10Gi para `models-ollama-0` en `dev`).

## Construir y validar en local

```bash
kustomize build k8s/overlays/dev
make kustomize policies test-policies trivy     # o: make check
```

`make kustomize` construye cada overlay y su Application, y los valida con kubeconform; `make policies` aplica las
reglas de manifiestos; `make trivy` analiza Terraform y los manifiestos renderizados.

## Sondas del backend

El backend usa `/actuator/health/liveness` (liveness y startup) y `/actuator/health/readiness`. La variable
`MANAGEMENT_ENDPOINT_HEALTH_PROBES_ENABLED=true` activa los grupos de sondas sin tocar el código de la aplicación.

## Añadir un servicio (desde F4)

Cada servicio nuevo incluye su base y sus overlays como parte de su Definition of Done.

1. Crea `k8s/base/<servicio>/` con `deployment.yaml` (o `statefulset.yaml`), `service.yaml` y `kustomization.yaml`.
   Define sondas, `resources` y `securityContext` (`runAsNonRoot`, `readOnlyRootFilesystem`, sin privilegios).
2. Si usa credenciales, añade `externalsecret.yaml` con la clave `/shoplab/ENVIRONMENT/<nombre>`; el parche de cada
   overlay ya reemplaza `ENVIRONMENT`. Si la credencial es otra, añade su clave remota al parche de los tres overlays.
3. Registra el directorio en `resources:` de `k8s/base/kustomization.yaml`.
4. En cada overlay: la imagen en `images:`, sus recursos en `patches/resources.yaml` y, si es sin estado, un HPA en
   `hpa.yaml` (sin `replicas` en el Deployment).
5. Ejecuta `make check`. Los tres overlays deben construir y pasar políticas y Trivy.
