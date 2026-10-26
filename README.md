# shoplab-infra

Infraestructura como código de ShopLab Helpdesk (LAB-98): Terraform contra un AWS emulado en local (Floci)
con un EKS local, ingress-nginx, External Secrets Operator, Argo CD y kube-prometheus-stack.

- Código: `terraform/` (módulos `state`, `eks`, `secrets`, `platform` y un entorno raíz por ambiente en `envs/`)
- Guía: `docs/terraform-local.md`
- Especificación: `specs/LAB-98-terraform-floci-eks/` en el repositorio `shoplab-helpdesk`

Uso previsto: `make up` levanta todo de cero; `make down` lo borra.

## Pipeline de CI (LAB-99)

Cada pull request y cada push a `main` ejecutan `.github/workflows/ci.yml`. La lógica de cada control vive en
`scripts/*.sh` y se invoca con `make`, de modo que en local se obtiene el mismo resultado que en CI.

| Job | Qué hace | Equivalente local |
| --- | --- | --- |
| `static` | `terraform fmt -check`, `validate`, TFLint, estructura/pines y `terraform test` de cada módulo | `make fmt-check validate lint pins tf-test` |
| `kustomize` | `kustomize build` de `k8s/overlays/{dev,staging,prod}`, `kubeconform -strict` y políticas de manifiestos (ver abajo) | `make kustomize policies test-policies` |
| `trivy` | Trivy config sobre `terraform/` (y, en `kustomize`, sobre los manifiestos renderizados); falla con HIGH/CRITICAL no exceptuados y sube el SARIF a Security | `make trivy` |
| `plan` | `terraform plan` contra un Floci efímero; lo publica como un único comentario del PR (se actualiza en cada push) | `make plan` (requiere Docker) |
| `smoke` | `terraform apply` sobre Floci, espera a que `shoplab-root` y `shoplab-dev` estén `Synced` y `Healthy` (y a que existan `shoplab-staging` y `shoplab-prod`), y destruye | `make smoke` (requiere Docker) |
| `ci-gate` | Resume el resultado: falla si algún job falló o se canceló; los omitidos no bloquean | — |

Checks requeridos del ruleset de `main` (`.github/rulesets/main-protection.json`): `ci-gate` y `pr-title`.

### Reproducir en local

```bash
make check-tools   # compara las herramientas instaladas con versions.env
make check         # fmt-check, validate, lint, pins, tf-test, kustomize, policies, test-policies y trivy
```

Sin `make` (Git Bash en Windows): `bash scripts/check-tools.sh`, `bash scripts/test.sh [fmt|checks|modules|validate]`,
`bash scripts/lint.sh`, `bash scripts/trivy.sh`.

### Versiones de las herramientas

`versions.env` es la única fuente de versiones (Terraform, TFLint y su plugin AWS, Trivy, kustomize, kubeconform, yq, imagen de Floci y tiempos
límite). El workflow y `make` la leen; `scripts/check-tools.sh` falla si lo instalado difiere
(`ALLOW_TOOL_DRIFT=1` lo convierte en aviso, solo para uso local). Si cambias la versión del plugin de TFLint o la
imagen de Floci, actualiza también `.tflint.hcl` y `docker-compose.yml`: el script lo comprueba.

### Overlays y políticas de manifiestos

`k8s/base` describe backend, frontend, ingest, Postgres con pgvector, Ollama e ingress; cada overlay de
`k8s/overlays/` (`dev`, `staging`, `prod`) fija namespace, imágenes, recursos, HPA y configuración, y
`k8s/argocd/` contiene la `Application` raíz (`root.yaml`, la crea Terraform) y una `Application` por ambiente que la
raíz gestiona (ver [docs/kustomize.md](docs/kustomize.md) y [docs/gitops.md](docs/gitops.md)). Al añadir un overlay hay
que listarlo en `OVERLAYS` de `versions.env`. `scripts/policy-check.sh` revisa la salida
renderizada (overlays y Applications) y falla con una línea `regla | overlay | recurso | valor` por violación:

| Regla | Falla si |
| --- | --- |
| `IMAGE_LATEST` | una imagen termina en `:latest` (también con digest) |
| `IMAGE_NO_TAG` | una imagen no tiene tag ni digest (un puerto de registro no cuenta como tag) |
| `TEMPLATE_REPO_URL` | aparece el placeholder `CAMBIA-ESTE-OWNER` |
| `TARGET_REVISION_NOT_MAIN` | el `targetRevision` de una `Application`/`ApplicationSet` no es `main` (ausente = `<unset>`) |
| `PLAIN_SECRET` | aparece un recurso `kind: Secret`; las credenciales se declaran como `ExternalSecret` (LAB-80) |
| `APPLICATION_NO_FINALIZER` | una `Application` no lleva el finalizer `resources-finalizer.argocd.argoproj.io` (LAB-79) |

`kubeconform` valida con el catálogo comunitario de CRDs y rechaza los recursos sin esquema. Las herramientas se
instalan en CI con `scripts/ci-install-tools.sh` (verifica el sha256 de cada descarga).

### Excepciones de Trivy

Se declaran en `.trivyignore`, una por línea, siempre precedidas de comentarios con el motivo, el responsable y la
fecha de revisión. No se acepta una excepción sin justificación; retírala cuando el hallazgo se corrija.

### Plan del PR

El estado de Terraform vive en un Floci nuevo en cada ejecución, así que el plan muestra siempre la creación
completa: sirve para detectar errores y revisar el conjunto de recursos, no un diff contra un entorno vivo. En PR
de forks o de Dependabot (token de solo lectura) el plan se escribe en el resumen del job.

### Ruleset de `main`

Se aplica una sola vez, después de que `ci-gate` y `pr-title` hayan corrido al menos una vez en el repositorio:

```bash
bash scripts/apply-ruleset.sh leandroAmariles/shoplab-infra
```
