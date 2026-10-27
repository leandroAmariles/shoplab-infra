# GitOps con Argo CD

Esta guía explica cómo llega un cambio al clúster, qué gestiona Terraform y qué gestiona Argo CD, cómo entrar a su
interfaz y qué hacer cuando un ambiente no sincroniza. La decisión de desplegar por pull y no desde Actions está en el
ADR-0006 del repositorio `shoplab-helpdesk` (`docs/adr/0006-gitops-pull-repo-infra-separado.md`). Los overlays que
Argo CD despliega se describen en [`kustomize.md`](kustomize.md) y el entorno local en
[`terraform-local.md`](terraform-local.md).

## Cómo llega un cambio al clúster

```text
rama → PR → CI (kustomize, kubeconform, políticas) → fusión a main → Argo CD detecta main → el clúster converge
```

1. Cambia el manifiesto en una rama (por ejemplo `k8s/overlays/dev/`) y abre una PR.
2. El CI valida el overlay `dev` y la `Application`: construye con `kustomize build`, valida el esquema y aplica las
   políticas (sin `:latest`, sin `Secret` en claro, `repoURL` real, `targetRevision: main` y finalizer).
3. Al fusionar en `main`, Argo CD lo detecta en el siguiente sondeo (unos 3 minutos) y sincroniza solo.
4. Verifica: `kubectl -n argocd get applications` debe mostrar `Synced` y `Healthy`.

No hay ningún comando de despliegue: el clúster refleja `main`.

## Qué hay en el clúster y quién lo gestiona

```text
Terraform ── instala ──▶ Argo CD (+ su ingress) ── crea ──▶ Application shoplab-root
                                                              └─ sincroniza k8s/argocd
                                                                   ├─ shoplab-dev → k8s/overlays/dev (ns shoplab-dev)
                                                                   └─ shoplab-observability → infra/observability de shoplab-helpdesk (ns monitoring)
```

Hay un único ambiente, `dev`: el nodo de k3s de Floci tiene unos 2 CPU y no cabe más de uno. La decisión y cómo añadir
otro ambiente si hiciera falta están en el ADR-0008 del repositorio `shoplab-helpdesk`
(`docs/adr/0008-un-solo-ambiente-dev.md`).

| Lo gestiona | Qué | Dónde cambia |
| --- | --- | --- |
| Terraform (plataforma) | Floci, clúster, secretos en Secrets Manager, ingress-nginx, External Secrets, monitorización, Argo CD y la `Application` raíz `shoplab-root` | `terraform/` y `k8s/argocd/root.yaml`; se aplica con `make up` / `terraform apply` |
| Argo CD (aplicaciones) | Backend, frontend, ingest, Postgres y Ollama de `dev`, y su `Application` | `k8s/overlays/` y `k8s/argocd/`; se aplica fusionando en `main` |

Regla práctica: si es un componente de la plataforma, va por Terraform; si es una aplicación de ShopLab, va por git.
La raíz es lo único de `k8s/argocd/` que cambia por Terraform: no se gestiona a sí misma y no figura en
`k8s/argocd/kustomization.yaml`.

### Estructura de `k8s/argocd/`

| Archivo | Función |
| --- | --- |
| `root.yaml` | `Application` raíz (app-of-apps). Terraform la lee y la crea al arrancar |
| `kustomization.yaml` | Lista las `Application` de `dev` y de los dashboards |
| `application-dev.yaml` | La `Application` de `dev`, apuntando a `k8s/overlays/dev` |
| `application-observability.yaml` | Dashboards de Grafana: lee `infra/observability` de `shoplab-helpdesk` (ver [`observability.md`](observability.md)) |

La raíz sincroniza este directorio (`root.yaml`, `spec.source.path: k8s/argocd`).

Toda `Application` lleva sincronización automática con `prune` y `selfHeal`, `repoURL` real, `targetRevision: main` y el finalizer
`resources-finalizer.argocd.argoproj.io` (retira los recursos al borrar la `Application`).

## Acceso a Argo CD

```bash
export KUBECONFIG=terraform/envs/dev/kubeconfig.yaml
kubectl -n ingress-nginx port-forward svc/ingress-nginx-controller 8080:80
```

Abre `http://argocd.localtest.me:8080` (`*.localtest.me` resuelve a 127.0.0.1). El usuario es `admin`; la contraseña
inicial se lee del clúster y no se guarda en el repositorio:

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

El mismo `port-forward` sirve el ingress de la aplicación (`shoplab.localtest.me:8080` en `dev`).

## Tareas habituales

### Cambiar un valor de `dev` y revertirlo

1. Edita, por ejemplo, el mínimo de réplicas en `k8s/overlays/dev/hpa.yaml`.
2. Abre la PR, espera al CI en verde y fusiona en `main`.
3. Observa: `kubectl -n argocd get application shoplab-dev -w` pasa a `OutOfSync` y vuelve a `Synced`.
4. Para revertir, usa `git revert` del commit de fusión y fusiona esa PR: Argo CD vuelve al estado anterior.

### Despliegue continuo a `dev` y su rollback

Cada versión publicada (tag `vX.Y.Z`) de `shoplab-helpdesk` fija en `k8s/overlays/dev/kustomization.yaml` ese tag, con un
commit del bot `shoplab-deploy[bot]` (LAB-81); no edites esas líneas a mano. Para volver atrás, revierte ese commit
mediante una PR. El flujo, la credencial y el procedimiento completo están en
[`despliegue-continuo.md`](https://github.com/leandroAmariles/shoplab-helpdesk/blob/main/docs/despliegue-continuo.md)
del repositorio de la aplicación.

### Añadir o quitar un ambiente o una `Application`

- Añadir un ambiente: sigue los pasos del ADR-0008 (overlay sobre `base/`, `k8s/argocd/application-<nombre>.yaml`
  listada en `k8s/argocd/kustomization.yaml`, `OVERLAYS` en `versions.env` y, si necesita clúster propio, otro entorno
  raíz de Terraform). Aparece en Argo CD tras fusionar. Recuerda que el nodo local solo tiene CPU para uno.
- Quitar: borra la línea de `kustomization.yaml` y el archivo. La raíz elimina la `Application` y, por el finalizer,
  también sus recursos.

### Si alguna vez se sincronizaron `staging` o `prod`

Hasta LAB-101 el repositorio definía también `staging` y `prod` (en local nunca se desplegaron). Si un clúster llegó a
tenerlos, al fusionar esta consolidación la raíz elimina sus `Application` (finalizer y `prune`). Si quedara algo
huérfano, límpialo a mano:

```bash
kubectl -n argocd delete application shoplab-staging shoplab-prod --ignore-not-found
kubectl delete namespace shoplab-staging shoplab-prod --ignore-not-found
```

Las claves `/shoplab/staging/...` y `/shoplab/prod/...` de Secrets Manager solo existen si se crearon con la variable
`app_environments`, que ya no existe; bórralas con la CLI de AWS si las hubiera.

### Cambiar la `Application` raíz

Edita `k8s/argocd/root.yaml`, fusiona y ejecuta `make up` (o `terraform apply`): es la única pieza que no se
actualiza sola, porque Terraform la crea.

## Diagnóstico

```bash
kubectl -n argocd get applications
kubectl -n argocd describe application shoplab-dev
```

| Estado | Causa habitual | Qué hacer |
| --- | --- | --- |
| `OutOfSync` que no converge | El overlay no construye o apunta a algo inexistente | Revisa la condición `ComparisonError` en `describe`; reproduce con `kustomize build k8s/overlays/dev` |
| `Synced` pero `Degraded` | Un pod no arranca o falta un secreto | `kubectl -n shoplab-dev get pods,externalsecret`; un `ExternalSecret` en error indica que falta la clave `/shoplab/dev/...` en Secrets Manager (no se muestran valores) |
| `Progressing` mucho tiempo | Descarga de imágenes o de modelos de Ollama | Espera; revisa `kubectl -n shoplab-dev describe pod` |
| `Application` ausente | La raíz aún no sincroniza o falta en `kustomization.yaml` | `kubectl -n argocd describe application shoplab-root` |

## Advertencias

- **No corrijas el clúster a mano.** Con `selfHeal`, Argo CD revierte cualquier cambio manual en minutos. Cambia git.
- **Todo lo desplegado en un ambiente debe estar en su overlay.** Con `prune`, lo que no está en git se elimina.
- **Las `Application` no contienen credenciales.** Los secretos de las aplicaciones llegan por `ExternalSecret`
  (ver [`kustomize.md`](kustomize.md)); el repositorio se lee sin credenciales porque es público.
- **El CI rechaza** un `repoURL` de plantilla (`CAMBIA-ESTE-OWNER`), un `targetRevision` distinto de `main`, una
  `Application` sin finalizer y una raíz listada en `k8s/argocd/kustomization.yaml`.
- **Local:** el único ambiente es `dev` (CPU del nodo de Floci). El k3s de Floci no trae `StorageClass`: la
  plataforma instala `local-path-provisioner` y deja `local-path` como clase por defecto, para que los PVC de Postgres
  y Ollama se enlacen (ver [`kustomize.md`](kustomize.md)).
- **Prueba de humo del CI:** exige `shoplab-root` `Synced` y `Healthy` y que cree `shoplab-dev`; no exige que `dev`
  quede `Healthy` por lo anterior. Como Argo CD sincroniza git y la PR aún no está en `main`, el smoke apunta la raíz a
  la revisión de la PR solo durante la prueba (`SMOKE_ROOT_REVISION`); `root.yaml` y las políticas siguen exigiendo
  `targetRevision: main`.
- **Puerto 8080:** si ya lo usa otra aplicación local, el `port-forward` no enlaza y las respuestas son de esa
  aplicación. Usa otro puerto (`... port-forward svc/ingress-nginx-controller 18080:80`) y
  `curl -H 'Host: argocd.localtest.me' http://127.0.0.1:18080/`.
