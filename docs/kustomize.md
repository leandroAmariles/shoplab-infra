# Manifiestos con Kustomize (`k8s/`)

El despliegue de ShopLab se describe de forma declarativa con Kustomize: una **base** común y un **overlay** para el
único ambiente, `dev`. Argo CD sincroniza el overlay desde `main`. Por qué hay un solo ambiente y cómo añadir otro: ADR-0008
del repositorio `shoplab-helpdesk`.

## Estructura

```text
k8s/
├── base/                    # backend, frontend, ingest, postgres (pgvector), ollama e ingress
│   ├── kustomization.yaml
│   └── <componente>/        # workload, service, ConfigMap generado y, si lleva credenciales, ExternalSecret
├── overlays/dev/            # namespace, imágenes de la app, recursos, HPA, host y claves de Secrets Manager
│   ├── kustomization.yaml
│   ├── namespace.yaml
│   ├── hpa.yaml
│   └── patches/resources.yaml
└── argocd/                  # Application raíz (root.yaml) y la de dev (application-dev.yaml)
```

La base no se despliega sola: no define namespace ni tags efectivos de las imágenes de la aplicación. El overlay `dev`
las fija. Kafka y los servicios de F4 no están en la base; se añaden como un componente más.

## Qué fija el overlay `dev`

| | dev |
| --- | --- |
| Namespace | `shoplab-dev` |
| HPA backend (mín–máx, CPU) | 1–2, 75% |
| HPA frontend | 1–2, 75% |
| HPA ingest | 1–2, 75% |
| Postgres | fuera del clúster: Docker del host, volumen propio (ver [Postgres en dev](#postgres-en-dev)) |
| Ollama | fuera del clúster: Docker del host (ver [Ollama en dev](#ollama-en-dev)) |
| Host del ingress | `shoplab.localtest.me` |
| Nivel de log del backend | `DEBUG` |

Los recursos por componente están en `overlays/dev/patches/resources.yaml`. Los Deployments no fijan `replicas`: las gobierna el HPA.

## Imágenes

Backend, frontend e ingest usan `ghcr.io/leandroamariles/<servicio>` y se fijan en `images:` del overlay `dev`. Hoy
van por **digest** de la imagen construida desde `main`, porque los tags `vX.Y.Z` (inmutables, LAB-78) aún no existen
en GHCR. Para obtener el digest de un commit:
`curl -sI -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.oci.image.index.v1+json" https://ghcr.io/v2/leandroamariles/<servicio>/manifests/<sha-completo>`
(cabecera `docker-content-digest`; el token anónimo sale de `https://ghcr.io/token?scope=repository:leandroamariles/<servicio>:pull`).
El despliegue continuo fija `newTag: vX.Y.Z` en cada release de `shoplab-helpdesk`. Postgres (`pgvector/pgvector`) y Ollama
llevan su versión en la base, la misma que `docker-compose.yml` de `shoplab-helpdesk`. Ninguna imagen puede usar
`latest` ni quedar sin tag: lo comprueba `scripts/policy-check.sh`.

## Secretos

No hay recursos `Secret` en git (regla `PLAIN_SECRET`). Cada componente que necesita una credencial declara un
`ExternalSecret` que lee de Secrets Manager mediante el `ClusterSecretStore` `aws-secrets-manager` (LAB-98). La base
usa la clave `/shoplab/ENVIRONMENT/postgres-password` y el overlay `dev` sustituye `ENVIRONMENT` por `dev`. Los
valores los crea el módulo `secrets` de Terraform: `make up` crea las claves `/shoplab/dev/...` porque el entorno raíz
es `dev`.

## Desplegar un overlay en el clúster local

`make up` deja Argo CD con la `Application` raíz `shoplab-root`, que crea `shoplab-dev` desde `main`: no hay que
aplicar nada a mano. Solo hay `dev` porque el nodo de k3s de Floci (unos 2 CPU) no tiene CPU para más de un ambiente; el
flujo completo y cómo entrar a la interfaz están en [`gitops.md`](gitops.md).

El k3s de Floci no trae `StorageClass`, así que `make up` instala `local-path-provisioner` (chart local
`terraform/modules/platform/charts/local-path-storage`) y deja `local-path` como clase por defecto: los PVC del clúster
se provisionan solos con volúmenes `hostPath` en el nodo desechable, con permisos 0777 (en `dev` ya no quedan PVC:
Postgres y Ollama corren en Docker). En un EKS real se usa la clase del clúster. Si cambias ese chart, sube su `version` en `Chart.yaml`: el provider de Helm no
detecta cambios en un chart local con la misma versión.

## Ollama en dev

En `dev` Ollama **no corre en el clúster**: lo sirve el contenedor `ollama` de `infra/docker-compose.yml` de
`shoplab-helpdesk` (puerto 11434 del host). Dentro del k3s de Floci el pod quedaba limitado a 2 CPU, sin GPU y
compartiendo nodo, y daba ~1 token/s y 7 s por embedding; en Docker con GPU son ~180 tokens/s y menos de 0,1 s.

El overlay quita el StatefulSet y los ConfigMap de Ollama, deja el Service `ollama` sin selector y lo dirige con un
EndpointSlice (`overlays/dev/ollama-host.yaml`) a `172.17.0.1:11434`, la puerta de enlace de la red `bridge` de Docker.
El backend y el ingest siguen usando `http://ollama:11434`. `host.docker.internal` no resuelve dentro del clúster.

- Antes de `make seed` o de usar el chat, el Ollama de Docker debe estar arriba:
  `docker compose -f infra/docker-compose.yml -f infra/docker-compose.gpu.yml up -d ollama` (sin el segundo `-f`
  corre en CPU).
- Si tu Docker usa otro rango, ajusta la dirección del EndpointSlice:
  `docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}'`.
- Solo aplica a `dev` (máquina del desarrollador); la base conserva el Ollama en el clúster para otros ambientes.

## Postgres en dev

Igual que Ollama, en `dev` Postgres **no corre en el clúster**: lo sirve el contenedor `postgres` de
`infra/docker-compose.yml` de `shoplab-helpdesk` (pgvector, puerto 5432 del host), con su volumen Docker
`shoplab_pgdata`. Así los datos (catálogo, pedidos, documentos y embeddings) sobreviven a `make down` y a un clúster
caído, y el backend arranca con la base que ya tiene. `overlays/dev/postgres-host.yaml` dirige el Service `postgres` a
`172.17.0.1:5432` y el overlay quita el StatefulSet, sus ConfigMap y su ExternalSecret.

- **La contraseña debe coincidir.** El backend la lee de Secrets Manager (`/shoplab/dev/postgres-password`, cargada por
  `make up` desde `terraform/envs/dev/secrets.auto.tfvars`). Pon ahí el mismo valor que `POSTGRES_PASSWORD` de
  `shoplab-helpdesk/infra/.env` (por defecto `change-me-local-only`) y ejecuta `make up` para actualizar el secreto.
- El Postgres de Docker debe estar arriba antes de que el backend arranque:
  `docker compose -f infra/docker-compose.yml up -d postgres`.
- Para conectar desde el host (IntelliJ, psql) usa directamente `localhost:5432`; ya no hay túnel.
- Las migraciones de Flyway las ejecuta el backend contra esa base: si la versión del backend desplegado es anterior a la
  que migró el volumen, Flyway puede rechazar el arranque.

## Construir y validar en local

```bash
kustomize build k8s/overlays/dev
make kustomize policies test-policies trivy     # o: make check
```

`make kustomize` construye el overlay `dev` y la Application, y los valida con kubeconform; `make policies` aplica las
reglas de manifiestos; `make trivy` analiza Terraform y los manifiestos renderizados.

## Sondas del backend

El backend usa `/actuator/health/liveness` (liveness y startup) y `/actuator/health/readiness`. La variable
`MANAGEMENT_ENDPOINT_HEALTH_PROBES_ENABLED=true` activa los grupos de sondas sin tocar el código de la aplicación.

## Añadir un servicio (desde F4)

Cada servicio nuevo incluye su base y su entrada en el overlay `dev` como parte de su Definition of Done.

1. Crea `k8s/base/<servicio>/` con `deployment.yaml` (o `statefulset.yaml`), `service.yaml` y `kustomization.yaml`.
   Define sondas, `resources` y `securityContext` (`runAsNonRoot`, `readOnlyRootFilesystem`, sin privilegios).
2. Si usa credenciales, añade `externalsecret.yaml` con la clave `/shoplab/ENVIRONMENT/<nombre>`; el parche de cada
   overlay ya reemplaza `ENVIRONMENT`. Si la credencial es otra, añade su clave remota al parche del overlay `dev`.
3. Registra el directorio en `resources:` de `k8s/base/kustomization.yaml`.
4. En el overlay `dev`: la imagen en `images:`, sus recursos en `patches/resources.yaml` y, si es sin estado, un HPA en
   `hpa.yaml` (sin `replicas` en el Deployment).
5. Ejecuta `make check`. El overlay `dev` debe construir y pasar políticas y Trivy.
